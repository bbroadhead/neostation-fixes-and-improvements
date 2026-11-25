import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/visual_profile.dart';
import '../../repositories/visual_profile_repository.dart';
import '../config_service.dart';
import '../logger_service.dart';
import 'gameplay_viewport.dart';
import 'installed_border.dart';

/// Private configuration for one launch of the detected Flatpak install.
class RetroArchVisualSession {
  RetroArchVisualSession._(this._config, this.arguments, this._scratch);

  static const _flatpakId = 'org.libretro.RetroArch';
  @visibleForTesting
  static String? homeOverride;

  static final _log = LoggerService.instance;

  final File _config;
  final List<Directory> _scratch;
  final List<String> arguments;

  static String get flatpakConfigRoot => path.join(
    homeOverride ?? ConfigService.getRealHomePath(),
    '.var',
    'app',
    _flatpakId,
    'config',
    'retroarch',
  );

  static Future<RetroArchVisualSession?> prepare({
    required String executable,
    required String systemId,
    required String? emulatorId,
    required String? romPath,
    required String corePath,
    String? systemFolder,
    ({int width, int height})? display,
    required List<String> arguments,
  }) async {
    if (!Platform.isLinux ||
        arguments.any(
          (arg) =>
              arg == '-c' ||
              arg.startsWith('-c') && !arg.startsWith('--') ||
              arg == '--config' ||
              arg.startsWith('--config=') ||
              arg.startsWith('--appendconfig') ||
              arg.startsWith('--set-shader'),
        )) {
      return null;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final repository = VisualProfileRepository(preferences);
      final profile = repository.resolve(
        systemId: systemId,
        emulatorId: emulatorId,
        romPath: romPath,
      );
      if (profile == null || !await _isFlatpakWrapper(executable)) return null;

      final configRoot = flatpakConfigRoot;
      final base = await File(path.join(configRoot, 'retroarch.cfg'))
          .readAsString();
      final selectedShader =
          profile.shaderId ??
          switch (profile.preset) {
            VisualPreset.enhanced => '@enhanced',
            VisualPreset.authentic when systemFolder != null =>
              _lcdSystems.contains(systemFolder) ? '@lcd' : '@crt',
            _ => null,
          };
      final shader = await _compatibleShader(
        configRoot,
        base,
        corePath,
        romPath,
        selectedShader,
      );
      final overrides = <String, String>{'config_save_on_exit': 'false'};
      if (selectedShader == '@none') overrides['video_shader_enable'] = 'false';
      if (profile.preset != VisualPreset.custom) {
        overrides.addAll({
          'video_force_aspect': 'true',
          'video_crop_overscan': 'false',
          'video_smooth': 'false',
        });
        final integerScale = switch (path.basenameWithoutExtension(corePath)) {
          'gambatte_libretro' ||
          'sameboy_libretro' ||
          'tgbdual_libretro' ||
          'mgba_libretro' ||
          'gpsp_libretro' ||
          'fceumm_libretro' ||
          'nestopia_libretro' => 'true',
          'ppsspp_libretro' ||
          'mupen64plus_next_libretro' ||
          'parallel_n64_libretro' ||
          'beetle_psx_hw_libretro' ||
          'mednafen_psx_hw_libretro' ||
          'swanstation_libretro' ||
          'citra_libretro' ||
          'melondsds_libretro' => 'false',
          _ => null,
        };
        if (integerScale != null) {
          overrides['video_scale_integer'] = integerScale;
          overrides['video_scale_integer_scaling'] = '0';
        }
      }

      Directory? artwork;
      String? appendedConfig;
      if (systemFolder != null &&
          display != null &&
          profile.borderId != null &&
          !base.contains('#include')) {
        try {
          final native = await _nativeOverrideFiles(
            configRoot,
            base,
            corePath,
            romPath,
          );
          if (native != null) {
            final conflicts = native.any(
              (file) => _hasNativeLayout(file.config),
            );
            if (!conflicts || _canReplayOverrides(native, romPath)) {
              final layout = <String, String>{};
              artwork = await _prepareBorder(
                configRoot,
                systemFolder,
                profile,
                layout,
                display,
                await _borderGeometry(
                  configRoot,
                  base,
                  corePath,
                  romPath,
                  systemFolder,
                ),
              );
              if (artwork != null) {
                if (conflicts) {
                  final finalLayout = File(
                    path.join(artwork.path, 'layout.cfg'),
                  );
                  await finalLayout.writeAsString(
                    _renderSettings({
                      ...layout,
                      'auto_overrides_enable': 'false',
                      'config_save_on_exit': 'false',
                    }),
                  );
                  appendedConfig = [
                    for (final file in native) file.filename,
                    finalLayout.path,
                  ].join('|');
                } else {
                  overrides.addAll(layout);
                }
              }
            }
          }
        } catch (error) {
          await artwork?.delete(recursive: true);
          artwork = null;
          _log.w('Could not apply RetroArch border: $error');
        }
      }

      Directory? coreOptions;
      try {
        coreOptions = await _prepareCoreOptions(
          configRoot,
          base,
          corePath,
          romPath,
          profile.preset,
          overrides,
        );
      } catch (error) {
        _log.w('Could not prepare RetroArch core options: $error');
      }
      final scratch = [?artwork, ?coreOptions];

      final filename =
          '.neostation-visual-'
          '${DateTime.now().microsecondsSinceEpoch}-'
          '${Random.secure().nextInt(1 << 30)}.cfg';
      final sessionConfig = File(path.join(configRoot, filename));
      var created = false;
      try {
        await sessionConfig.create(exclusive: true);
        created = true;
        await sessionConfig.writeAsString(
          _renderConfig(overrides),
          flush: true,
        );
      } catch (_) {
        if (created) await sessionConfig.delete();
        for (final directory in scratch) {
          await directory.delete(recursive: true);
        }
        rethrow;
      }
      return RetroArchVisualSession._(sessionConfig, [
        '--config=${sessionConfig.path}',
        if (appendedConfig != null) '--appendconfig=$appendedConfig',
        if (shader != null) '--set-shader=$shader',
        ...arguments,
      ], scratch);
    } catch (error) {
      _log.w('Could not prepare RetroArch visual profile: $error');
      return null;
    }
  }

  static Future<({bool? achievements, bool? hardcore, bool accountMatches})?>
  configuredAchievementSettings({
    required String executable,
    required String coreFilename,
    required String romPath,
    required String username,
  }) async {
    if (!Platform.isLinux || !await _isFlatpakWrapper(executable)) return null;
    final root = flatpakConfigRoot;
    final base = await File(path.join(root, 'retroarch.cfg')).readAsString();
    final overrides = await _nativeOverrides(root, base, coreFilename, romPath);
    if (overrides == null) return null;
    final configs = [base, ...overrides];
    if (configs.any((config) => config.contains('#include'))) return null;
    String? setting(String key) => configs.reversed
        .map((config) => _value(config, key))
        .whereType<String>()
        .firstOrNull;
    bool? flag(String key) => switch (setting(key)) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    return (
      achievements: flag('cheevos_enable'),
      hardcore: flag('cheevos_hardcore_mode_enable'),
      accountMatches:
          setting('cheevos_username')?.toLowerCase() ==
              username.toLowerCase() &&
          ((setting('cheevos_token')?.isNotEmpty ?? false) ||
              (setting('cheevos_password')?.isNotEmpty ?? false)),
    );
  }

  static Future<bool> _isFlatpakWrapper(String executable) async {
    if (path.basename(executable) == _flatpakId) return true;
    final file = File(executable);
    if (await file.length() > 64 * 1024) return false;
    final contents = utf8.decode(
      await file.readAsBytes(),
      allowMalformed: true,
    );
    if (!contents.startsWith('#!')) return false;
    return const LineSplitter()
        .convert(contents)
        .any(
          RegExp(
            r'^\s*(?:exec\s+)?(?:/usr/bin/)?flatpak\s+run\s+org\.libretro\.RetroArch(?:\s|$)',
          ).hasMatch,
        );
  }

  static String? _value(String config, String key) => RegExp(
    '^\\s*${RegExp.escape(key)}\\s*=\\s*"([^"]+)"',
    multiLine: true,
  ).firstMatch(config)?.group(1);

  static Future<({String core, String directory})?> _coreLocation(
    String root,
    String config,
    String corePath,
  ) async {
    final info = File(
      path.join(
        root,
        'info',
        '${path.basenameWithoutExtension(corePath)}.info',
      ),
    );
    if (!await info.exists()) return null;
    final core = _value(await info.readAsString(), 'corename');
    if (core == null || core != path.basename(core) || core == '..') {
      return null;
    }
    final configured = _value(config, 'rgui_config_directory');
    final configDirectory = switch (configured) {
      null || 'default' => path.join(root, 'config'),
      _ when configured.startsWith('~/') => path.join(
        homeOverride ?? ConfigService.getRealHomePath(),
        configured.substring(2),
      ),
      _ when path.isAbsolute(configured) => configured,
      _ => null,
    };
    return configDirectory == null
        ? null
        : (core: core, directory: configDirectory);
  }

  static Future<List<String>?> _nativeOverrides(
    String root,
    String config,
    String corePath,
    String? romPath,
  ) async {
    final files = await _nativeOverrideFiles(root, config, corePath, romPath);
    return files?.map((file) => file.config).toList();
  }

  static Future<List<({String filename, String config})>?> _nativeOverrideFiles(
    String root,
    String config,
    String corePath,
    String? romPath,
  ) async {
    if (_value(config, 'auto_overrides_enable') == 'false') return [];
    final location = await _coreLocation(root, config, corePath);
    if (location == null) return null;
    final (core: core, directory: configDirectory) = location;

    final names = [
      core,
      if (romPath != null) ...[
        path.basename(path.dirname(romPath)),
        path.basenameWithoutExtension(romPath),
      ],
    ];
    final contents = <({String filename, String config})>[];
    for (final name in names.toSet()) {
      final override = File(path.join(configDirectory, core, '$name.cfg'));
      if (await override.exists()) {
        contents.add((
          filename: override.path,
          config: await override.readAsString(),
        ));
      }
    }
    return contents;
  }

  static Future<Directory?> _prepareCoreOptions(
    String root,
    String base,
    String corePath,
    String? romPath,
    VisualPreset preset,
    Map<String, String> overrides,
  ) async {
    if (preset == VisualPreset.custom ||
        base.contains('#include') ||
        romPath == null ||
        romPath.contains('#') ||
        const {'.zip', '.7z'}.contains(path.extension(romPath).toLowerCase())) {
      return null;
    }

    final authentic = preset == VisualPreset.authentic;
    final enhanced = preset == VisualPreset.enhanced;
    final adjustment = switch (path.basenameWithoutExtension(corePath)) {
      'citra_libretro' => (
        key: 'citra_resolution_factor',
        target: authentic
            ? '1x (Native)'
            : enhanced
            ? '3x'
            : '2x',
      ),
      'mupen64plus_next_libretro' => (
        key: 'mupen64plus-43screensize',
        target: authentic
            ? '320x240'
            : enhanced
            ? '1280x960'
            : '960x720',
      ),
      'flycast_libretro' => (
        key: 'reicast_internal_resolution',
        target: authentic
            ? '640x480'
            : enhanced
            ? '1280x960'
            : '960x720',
      ),
      'ppsspp_libretro' => (
        key: 'ppsspp_internal_resolution',
        target: authentic
            ? '480x272'
            : enhanced
            ? '1920x1088'
            : '1440x816',
      ),
      'mednafen_psx_hw_libretro' || 'beetle_psx_hw_libretro' => (
        key: 'beetle_psx_hw_internal_resolution',
        target: authentic
            ? '1x'
            : enhanced
            ? '4x'
            : '2x',
      ),
      'swanstation_libretro' => (
        key: 'duckstation_GPU.ResolutionScale',
        target: authentic
            ? '1'
            : enhanced
            ? '4'
            : '3',
      ),
      _ => null,
    };
    if (adjustment == null) return null;
    final source = await _optionsSource(root, base, corePath, romPath);
    if (source == null) return null;
    final original = await source.readAsString();
    final existing = _value(original, adjustment.key);
    if (existing == null || original.contains('#include')) return null;
    final resolution = RegExp(r'^\d+').stringMatch(existing);
    final target = RegExp(r'^\d+').stringMatch(adjustment.target)!;
    if (!authentic &&
        (resolution == null || int.parse(resolution) >= int.parse(target))) {
      return null;
    }

    final directory = await Directory(root)
        .createTemp('.neostation-core-options-');
    try {
      final config = File(path.join(directory.path, 'core-options.cfg'));
      final key = RegExp.escape(adjustment.key);
      await config.writeAsString(
        original.replaceFirst(
          RegExp('^\\s*$key\\s*=.*\$', multiLine: true),
          '${adjustment.key} = "${adjustment.target}"',
        ),
      );
      overrides['global_core_options'] = 'true';
      overrides['game_specific_options'] = 'false';
      overrides['core_options_path'] = config.path;
      return directory;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  static Future<File?> _optionsSource(
    String root,
    String base,
    String corePath,
    String? romPath, {
    bool includeContent = false,
  }) async {
    final location = await _coreLocation(root, base, corePath);
    final native = await _nativeOverrides(root, base, corePath, romPath);
    if (location == null ||
        native == null ||
        native.any(
          (config) =>
              config.contains('#include') ||
              RegExp(
                r'^\s*(global_core_options|game_specific_options|core_options_path|rgui_config_directory)\s*=',
                multiLine: true,
              ).hasMatch(config),
        )) {
      return null;
    }

    final options = path.join(location.directory, location.core);
    if (romPath != null && _value(base, 'game_specific_options') != 'false') {
      for (final name in [
        path.basenameWithoutExtension(romPath),
        path.basename(path.dirname(romPath)),
      ]) {
        final override = File(path.join(options, '$name.opt'));
        if (await override.exists()) return includeContent ? override : null;
      }
    }

    final configured = _value(base, 'core_options_path');
    final global = switch (configured) {
      null => path.join(root, 'retroarch-core-options.cfg'),
      _ when path.isAbsolute(configured) => configured,
      _ => null,
    };
    final coreOptions = File(path.join(options, '${location.core}.opt'));
    final useCore =
        _value(base, 'global_core_options') != 'true' &&
        await coreOptions.exists();
    if (!useCore && global == null) return null;
    final source = useCore ? coreOptions : File(global!);
    if (!await source.exists()) return null;
    return source;
  }

  static Future<({double aspect, int? nativeHeight})?> previewBorderGeometry({
    required String system,
    required String? coreFilename,
    String? romPath,
  }) async {
    final fallback = InstalledBorder.geometry(system);
    final family = system.replaceFirst(RegExp(r'-hacks$'), '');
    if (!const {'ws', 'wsc', 'ds', '3ds'}.contains(family)) return fallback;
    if (coreFilename == null) return null;
    try {
      final root = flatpakConfigRoot;
      final base = await File(path.join(root, 'retroarch.cfg')).readAsString();
      if (base.contains('#include')) return null;
      return await _borderGeometry(root, base, coreFilename, romPath, system);
    } on FileSystemException {
      return null;
    }
  }

  static Future<({double aspect, int? nativeHeight})?> _borderGeometry(
    String root,
    String base,
    String corePath,
    String? romPath,
    String system,
  ) async {
    final family = system.replaceFirst(RegExp(r'-hacks$'), '');
    if (!const {'ws', 'wsc', 'ds', '3ds'}.contains(family)) {
      return InstalledBorder.geometry(system);
    }
    if (romPath != null &&
        (romPath.contains('#') ||
            const {
              '.zip',
              '.7z',
            }.contains(path.extension(romPath).toLowerCase()))) {
      return null;
    }
    final expectedCore = switch (family) {
      'ds' => 'melonds_libretro',
      '3ds' => 'citra_libretro',
      _ => 'mednafen_wswan_libretro',
    };
    final core = path.basenameWithoutExtension(corePath);
    final modernMelonDs = family == 'ds' && core == 'melondsds_libretro';
    if (core != expectedCore && !modernMelonDs) return null;
    final source = await _optionsSource(
      root,
      base,
      corePath,
      romPath,
      includeContent: true,
    );
    if (source == null) return null;
    final config = await source.readAsString();
    if (config.contains('#include')) return null;
    if (family == '3ds') {
      return switch (_value(config, 'citra_layout_option')) {
        null ||
        'Default Top-Bottom Screen' => (aspect: 5 / 6, nativeHeight: 480),
        'Side by Side' => (aspect: 3.0, nativeHeight: 240),
        'Large Screen, Small Screen' => (aspect: 2.0, nativeHeight: 960),
        _ => null,
      };
    }
    if (family == 'ds') {
      final gap = int.tryParse(_value(config, 'melonds_screen_gap') ?? '');
      if (gap == null || gap < 0 || gap > 126 || (!modernMelonDs && gap != 0)) {
        return null;
      }
      if (modernMelonDs) {
        if (_value(config, 'melonds_number_of_screen_layouts') != '1') {
          return null;
        }
        return switch (_value(config, 'melonds_screen_layout1')) {
          'left-right' ||
          'right-left' when gap == 0 => (aspect: 8 / 3, nativeHeight: 192),
          'top-bottom' ||
          'bottom-top' => (aspect: 256 / (384 + gap), nativeHeight: 384 + gap),
          _ => null,
        };
      }
      return switch (_value(config, 'melonds_screen_layout')) {
        'Left/Right' || 'Right/Left' => (aspect: 8 / 3, nativeHeight: 192),
        'Top/Bottom' || 'Bottom/Top' => (aspect: 2 / 3, nativeHeight: 384),
        _ => null,
      };
    }
    return switch (_value(config, 'wswan_rotate_display')) {
      'landscape' => (aspect: 14 / 9, nativeHeight: 144),
      'portrait' when _value(base, 'video_allow_rotate') != 'false' => (
        aspect: 9 / 14,
        nativeHeight: 224,
      ),
      _ => null,
    };
  }

  static bool _canReplayOverrides(
    List<({String filename, String config})> native,
    String? romPath,
  ) {
    if (romPath == null ||
        romPath.contains('#') ||
        const {'.zip', '.7z'}.contains(path.extension(romPath).toLowerCase())) {
      return false;
    }
    final unsafe = RegExp(
      r'^\s*(?:#include\b|(?:video_rotation|video_driver|rgui_config_directory)\s*=)',
      multiLine: true,
    );
    return native.every(
      (file) => !file.filename.contains('|') && !unsafe.hasMatch(file.config),
    );
  }

  static bool _hasNativeLayout(String config) => RegExp(
    r'^\s*(?:(?:custom_viewport_|input_overlay|video_scale_integer|video_rotation|video_fullscreen|video_windowed_fullscreen|video_viewport_bias)\w*|aspect_ratio_index|video_force_aspect)\s*=|^\s*#include ',
    multiLine: true,
  ).hasMatch(config);

  static Future<Directory?> _prepareBorder(
    String root,
    String system,
    VisualProfile profile,
    Map<String, String> overrides,
    ({int width, int height}) display,
    ({double aspect, int? nativeHeight})? geometry,
  ) async {
    if (geometry == null) return null;
    for (final border in await InstalledBorder.discover(root, system)) {
      if (border.id != profile.borderId) continue;
      final rendered = await border.render(geometry.aspect, display: display);
      if (rendered == null) return null;
      final viewport = border.stackedDs
          ? rendered.opening
          : GameplayViewport.fit(
              opening: rendered.opening,
              aspectRatio: geometry.aspect,
              nativeHeight: geometry.nativeHeight,
              size: profile.size.clamp(0.25, 1.0),
              horizontal: profile.horizontal,
              vertical: profile.vertical,
            );
      if (viewport == null) return null;
      final scratch = await Directory(root).createTemp('.neostation-border-');
      try {
        await File(path.join(scratch.path, 'border.png'))
            .writeAsBytes(rendered.png);
        await File(path.join(scratch.path, 'border.cfg')).writeAsString(
          'overlays = 1\noverlay0_overlay = border.png\n'
          'overlay0_full_screen = true\noverlay0_descs = 0\n',
        );
        overrides.addAll({
          // ASPECT_RATIO_CUSTOM in RetroArch 1.22.
          'aspect_ratio_index': '23',
          'video_fullscreen': 'true',
          'video_fullscreen_x': '0',
          'video_fullscreen_y': '0',
          'video_windowed_fullscreen': 'true',
          'video_force_aspect': 'true',
          'video_crop_overscan': 'false',
          'video_scale_integer': 'false',
          // RetroArch adds the viewport bias to these absolute coordinates.
          'video_viewport_bias_x': '0.0',
          'video_viewport_bias_y': '0.0',
          'custom_viewport_x': '${viewport.x}',
          'custom_viewport_y': '${viewport.y}',
          'custom_viewport_width': '${viewport.width}',
          'custom_viewport_height': '${viewport.height}',
          'input_overlay': path.join(scratch.path, 'border.cfg'),
          'input_overlay_enable': 'true',
          'input_overlay_enable_autopreferred': 'false',
          'input_overlay_auto_scale': 'false',
          'input_overlay_auto_rotate': 'false',
          'input_overlay_hide_when_gamepad_connected': 'false',
          'input_overlay_opacity': '1.0',
          for (final orientation in ['landscape', 'portrait']) ...{
            'input_overlay_scale_$orientation': '1.0',
            'input_overlay_aspect_adjust_$orientation': '0.0',
            'input_overlay_x_offset_$orientation': '0.0',
            'input_overlay_y_offset_$orientation': '0.0',
          },
        });
        return scratch;
      } catch (_) {
        await scratch.delete(recursive: true);
        rethrow;
      }
    }
    return null;
  }

  static const _lcdSystems = {
    'gb',
    'gbc',
    'gba',
    'gg',
    'gamegear',
    'ngp',
    'ngpc',
    'ws',
    'wsc',
    'psp',
    'ds',
    '3ds',
    'atarilynx',
  };

  static String? _presetPath(String id, String format) {
    final directory = switch ((id, format)) {
      ('@sharp', 'slang') => 'pixel-art-scaling/sharp-bilinear-simple',
      ('@sharp', 'glsl') => 'interpolation/sharp-bilinear-simple',
      ('@enhanced', 'slang') => 'interpolation/jinc2-sharp',
      ('@enhanced', 'glsl') => 'interpolation/sharp-bilinear-simple',
      ('@lcd', _) => 'handheld/lcd-grid-v2',
      ('@crt', _) => 'crt/crt-pi',
      _ => null,
    };
    return directory == null ? null : 'shaders_$format/$directory.${format}p';
  }

  static Future<String?> _compatibleShader(
    String root,
    String config,
    String corePath,
    String? romPath,
    String? shaderId,
  ) async {
    if (shaderId == null || path.isAbsolute(shaderId)) return null;
    final format = await _shaderFormat(root, config, corePath, romPath);
    if (format == null) return null;
    final relativePath = shaderId.startsWith('@')
        ? _presetPath(shaderId, format)
        : shaderId;
    if (relativePath == null || path.extension(relativePath) != '.${format}p') {
      return null;
    }
    final shaders = Directory(path.join(root, 'shaders'));
    final file = File(path.join(shaders.path, relativePath));
    if (!await file.exists()) return null;
    final canonical = await file.resolveSymbolicLinks();
    return path.isWithin(await shaders.resolveSymbolicLinks(), canonical)
        ? canonical
        : null;
  }

  static Future<String?> previewShaderFormat({
    required String? coreFilename,
    String? romPath,
  }) async {
    if (coreFilename == null) return null;
    final root = flatpakConfigRoot;
    try {
      final config = await File(path.join(root, 'retroarch.cfg'))
          .readAsString();
      return await _shaderFormat(root, config, coreFilename, romPath);
    } on FileSystemException {
      return null;
    }
  }

  static Future<String?> _shaderFormat(
    String root,
    String config,
    String corePath,
    String? romPath,
  ) async {
    final native = await _nativeOverrides(root, config, corePath, romPath);
    if (native == null) return null;
    var driver = _value(config, 'video_driver');
    for (final override in native) {
      driver = _value(override, 'video_driver') ?? driver;
    }
    return switch (driver) {
      'vulkan' || 'glcore' => 'slang',
      'gl' => 'glsl',
      _ => null,
    };
  }

  /// Native includes inherit all base settings while leaving the base config
  /// outside the session's write path.
  static String _renderConfig(Map<String, String> overrides) =>
      '${_renderSettings(overrides)}#include "retroarch.cfg"\n';

  static String _renderSettings(Map<String, String> overrides) {
    final output = StringBuffer();
    for (final setting in overrides.entries) {
      output.writeln('${setting.key} = "${setting.value}"');
    }
    return output.toString();
  }

  Future<void> dispose() async {
    try {
      await _config.delete();
      for (final directory in _scratch) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException catch (error) {
      _log.w('Could not remove temporary RetroArch configuration: $error');
    }
  }
}
