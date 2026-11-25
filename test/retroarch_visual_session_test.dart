import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/visual_profile.dart';
import 'package:neostation/repositories/visual_profile_repository.dart';
import 'package:neostation/services/visual_profiles/retroarch_visual_session.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late Directory root;
  late File base;
  late File wrapper;
  late VisualProfileRepository profiles;
  const scope = (systemId: 'psp', emulatorId: null);
  const args = ['-f', '-L', '/cores/ppsspp_libretro.so', '/games/Game.iso'];
  const settings =
      'video_driver = "vulkan"\ncheevos_enable = "true"\n'
      'cheevos_hardcore_mode_enable = "true"\nconfig_save_on_exit = "true"\n';

  Future<RetroArchVisualSession?> prepare({List<String> arguments = args}) =>
      RetroArchVisualSession.prepare(
        executable: wrapper.path,
        systemId: scope.systemId,
        emulatorId: 'psp.ra.ppsspp',
        romPath: args.last,
        corePath: args[2],
        arguments: arguments,
      );

  setUp(() async {
    home = await Directory.systemTemp.createTemp('visual-session-test-');
    RetroArchVisualSession.homeOverride = home.path;
    root = await Directory(
      path.join(home.path, '.var/app/org.libretro.RetroArch/config/retroarch'),
    ).create(recursive: true);
    final info = await Directory(path.join(root.path, 'info')).create();
    await File(path.join(info.path, 'ppsspp_libretro.info'))
        .writeAsString('corename = "PPSSPP"');
    base = await File(path.join(root.path, 'retroarch.cfg'))
        .writeAsString(settings);
    wrapper = await File(
      path.join(home.path, 'retroarch.sh'),
    ).writeAsString('#!/bin/bash\nflatpak run org.libretro.RetroArch "\$@"\n');
    SharedPreferences.setMockInitialValues({});
    profiles = VisualProfileRepository(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    RetroArchVisualSession.homeOverride = null;
    await home.delete(recursive: true);
  });

  test('uses a session config only for opted-in launches', () async {
    expect(await prepare(), isNull);
    expect(await profiles.save(scope, const VisualProfile()), isTrue);

    final first = (await prepare())!;
    final second = (await prepare())!;
    final usedConfig = File(
      first.arguments.first.substring('--config='.length),
    );
    expect(first.arguments.skip(1), args);
    expect(first.arguments.first, isNot(second.arguments.first));
    expect(usedConfig.parent.path, root.path);
    expect(
      await usedConfig.readAsString(),
      contains('#include "retroarch.cfg"'),
    );
    expect(
      await usedConfig.readAsString(),
      contains('config_save_on_exit = "false"'),
    );
    expect(await base.readAsString(), settings);
    await first.dispose();
    expect(await usedConfig.exists(), isFalse);
    await second.dispose();
  }, skip: !Platform.isLinux);

  test('respects an explicitly supplied config', () async {
    await profiles.save(scope, const VisualProfile());
    expect(await prepare(arguments: ['--config=/custom.cfg', ...args]), isNull);
  }, skip: !Platform.isLinux);

  test(
    'passes only an existing backend-compatible shader to the wrapper',
    () async {
      final shaders = await Directory(path.join(root.path, 'shaders')).create();
      final shader = await File(path.join(shaders.path, 'sharp.slangp'))
          .create();
      await profiles.save(scope, const VisualProfile(shaderId: 'sharp.slangp'));
      final first = (await prepare())!;
      expect(first.arguments, contains('--set-shader=${shader.path}'));
      await first.dispose();

      final overrides = await Directory(
        path.join(root.path, 'config', 'PPSSPP'),
      ).create(recursive: true);
      await File(path.join(overrides.path, 'Game.cfg'))
          .writeAsString('video_driver = "gl"');
      final second = (await prepare())!;
      expect(second.arguments.skip(1), args);
      await second.dispose();
    },
    skip: !Platform.isLinux,
  );
  Future<void> createTestBorder(Directory pack, String name) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src)
      ..drawRect(
        const ui.Rect.fromLTWH(200, 80, 240, 216),
        ui.Paint()..blendMode = ui.BlendMode.clear,
      );
    final picture = recorder.endRecording();
    final image = await picture.toImage(640, 400);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File(path.join(pack.path, '$name.png')).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    image.dispose();
    picture.dispose();
    await File(path.join(pack.path, '$name.cfg')).writeAsString(
      'overlays = 1\noverlay0_overlay = $name.png\n'
      'overlay0_full_screen = true\noverlay0_descs = 0\n',
    );
  }

  test(
    'installs a session-local overlay at the active display dimensions',
    () async {
      const borderScope = (systemId: 'gb', emulatorId: null);
      final pack = await Directory(path.join(root.path, 'overlays', 'borders'))
          .create(recursive: true);
      await createTestBorder(pack, 'gb');
      await profiles.save(borderScope, const VisualProfile(borderId: 'gb'));
      await base.writeAsString('${settings}auto_overrides_enable = "false"\n');

      Future<RetroArchVisualSession> game(int width, int height) async =>
          (await RetroArchVisualSession.prepare(
            executable: wrapper.path,
            systemId: borderScope.systemId,
            systemFolder: 'gb',
            emulatorId: null,
            romPath: '/games/Game.gb',
            corePath: '/cores/gambatte_libretro.so',
            display: (width: width, height: height),
            arguments: args,
          ))!;

      final session = await game(1280, 800);
      final config = File(
        session.arguments.first.substring('--config='.length),
      );
      final contents = await config.readAsString();
      expect(contents, contains('aspect_ratio_index = "23"'));
      expect(contents, contains('video_viewport_bias_x = "0.0"'));
      expect(contents, contains('video_viewport_bias_y = "0.0"'));

      expect(contents, contains('input_overlay_enable = "true"'));
      final scratch = root.listSync().whereType<Directory>().singleWhere(
        (directory) =>
            path.basename(directory.path).startsWith('.neostation-border-'),
      );
      expect(
        await File(path.join(scratch.path, 'border.png')).exists(),
        isTrue,
      );
      await session.dispose();
      expect(await scratch.exists(), isFalse);

      final otherDisplay = await game(1920, 1080);
      final otherConfig = File(
        otherDisplay.arguments.first.substring('--config='.length),
      );
      expect(await otherConfig.readAsString(), contains('input_overlay ='));
      await otherDisplay.dispose();
    },
    skip: !Platform.isLinux,
  );
  test('replays native override settings before an opted-in border', () async {
    final pack = await Directory(path.join(root.path, 'overlays', 'borders'))
        .create(recursive: true);
    await createTestBorder(pack, 'psp');
    final native = await Directory(path.join(root.path, 'config', 'PPSSPP'))
        .create(recursive: true);
    final core = await File(path.join(native.path, 'PPSSPP.cfg')).writeAsString(
      'input_overlay = "native.cfg"\ninput_player1_joypad_index = "2"',
    );
    final folder = await File(path.join(native.path, 'games.cfg'))
        .writeAsString('aspect_ratio_index = "21"');
    final game = await File(path.join(native.path, 'Game.cfg'))
        .writeAsString('audio_volume = "-4"');
    Future<RetroArchVisualSession> launch(String? border) async {
      await profiles.save(scope, VisualProfile(borderId: border));
      return (await RetroArchVisualSession.prepare(
        executable: wrapper.path,
        systemId: scope.systemId,
        systemFolder: 'psp',
        emulatorId: 'psp.ra.ppsspp',
        romPath: args.last,
        corePath: args[2],
        display: (width: 1280, height: 800),
        arguments: args,
      ))!;
    }

    final session = await launch('psp');
    final files = session.arguments
        .singleWhere((arg) => arg.startsWith('--appendconfig='))
        .substring('--appendconfig='.length)
        .split('|');
    expect(files.take(3), [core.path, folder.path, game.path]);
    final generated = File(files.last);
    expect(
      await generated.readAsString(),
      contains('auto_overrides_enable = "false"'),
    );
    expect(
      await generated.readAsString(),
      contains('aspect_ratio_index = "23"'),
    );
    expect(await core.readAsString(), contains('input_overlay = "native.cfg"'));
    await session.dispose();
    expect(await generated.exists(), isFalse);

    final noBorder = await launch(null);
    expect(noBorder.arguments.skip(1), args);
    await noBorder.dispose();

    await game.writeAsString('video_rotation = "1"');
    final rotated = await launch('psp');
    expect(rotated.arguments.skip(1), args);
    await rotated.dispose();
  }, skip: !Platform.isLinux);

  test(
    'Enhanced resolves its installed shader while preserving the ROM and core',
    () async {
      final shaderDirectory = await Directory(
        path.join(root.path, 'shaders', 'shaders_slang', 'interpolation'),
      ).create(recursive: true);
      final shader = await File(
        path.join(shaderDirectory.path, 'jinc2-sharp.slangp'),
      ).create();
      expect(
        await profiles.save(
          scope,
          const VisualProfile(preset: VisualPreset.enhanced),
        ),
        isTrue,
      );
      final session = (await prepare())!;
      expect(session.arguments, contains('--set-shader=${shader.path}'));
      expect(session.arguments.skip(2), args);
      await session.dispose();
    },
    skip: !Platform.isLinux,
  );
  test(
    'a game profile inherits again when its core-specific override is reset',
    () async {
      const coreScope = (systemId: 'psp', emulatorId: 'psp.ra.ppsspp');
      await profiles.save(scope, const VisualProfile());
      await profiles.save(
        coreScope,
        const VisualProfile(preset: VisualPreset.custom),
        gameKey: args.last,
      );
      Future<String> configForGame() async {
        final session = (await prepare())!;
        try {
          final config = File(
            session.arguments.first.substring('--config='.length),
          );
          return await config.readAsString();
        } finally {
          await session.dispose();
        }
      }

      expect(await configForGame(), isNot(contains('video_smooth')));
      await profiles.reset(coreScope, gameKey: args.last);
      expect(await configForGame(), contains('video_smooth = "false"'));
    },
    skip: !Platform.isLinux,
  );
  test(
    'raises PSP rendering resolution using an isolated options copy',
    () async {
      final directory = await Directory(
        path.join(root.path, 'config', 'PPSSPP'),
      ).create(recursive: true);
      const original =
          'ppsspp_internal_resolution = "480x272"\n'
          'ppsspp_texture_filtering = "Auto"\n';
      final options = await File(path.join(directory.path, 'PPSSPP.opt'))
          .writeAsString(original);
      await profiles.save(scope, const VisualProfile());

      final session = (await prepare())!;
      final config = File(
        session.arguments.first.substring('--config='.length),
      );
      final optionsPath = RegExp(r'core_options_path = "([^"]+)"')
          .firstMatch(await config.readAsString())!
          .group(1)!;
      final contents = await File(optionsPath).readAsString();
      expect(contents, contains('ppsspp_internal_resolution = "1440x816"'));
      expect(contents, contains('ppsspp_texture_filtering = "Auto"'));
      expect(await options.readAsString(), original);
      expect(session.arguments.skip(1), args);
      await session.dispose();
      expect(await File(optionsPath).exists(), isFalse);

      await File(path.join(directory.path, 'games.opt'))
          .writeAsString(original);
      final native = (await prepare())!;
      final nativeConfig = File(
        native.arguments.first.substring('--config='.length),
      );
      expect(
        await nativeConfig.readAsString(),
        isNot(contains('core_options_path')),
      );
      await native.dispose();
    },
    skip: !Platform.isLinux,
  );
  test(
    'fits fixed WonderSwan, DS and 3DS layouts from native options',
    () async {
      await base.writeAsString('${settings}auto_overrides_enable = "false"\n');
      final overlays = await Directory(
        path.join(root.path, 'overlays', 'pegasus'),
      ).create(recursive: true);
      await createTestBorder(overlays, 'wswanc');
      await createTestBorder(overlays, 'ds');
      await createTestBorder(overlays, '3ds');

      Future<String> configFor(
        String system,
        String core,
        String label,
        String native,
        String border,
        String filename,
      ) async {
        await File(path.join(root.path, 'info', '${core}_libretro.info'))
            .writeAsString('corename = "$label"');
        final directory = await Directory(path.join(root.path, 'config', label))
            .create(recursive: true);
        await File(path.join(directory.path, '$label.opt'))
            .writeAsString(native);
        await profiles.save((
          systemId: system,
          emulatorId: null,
        ), VisualProfile(borderId: border));
        final session = (await RetroArchVisualSession.prepare(
          executable: wrapper.path,
          systemId: system,
          systemFolder: system,
          emulatorId: null,
          romPath: '/games/$filename',
          corePath: '/cores/${core}_libretro.so',
          display: (width: 1280, height: 800),
          arguments: args,
        ))!;
        try {
          return await File(
            session.arguments.first.substring('--config='.length),
          ).readAsString();
        } finally {
          await session.dispose();
        }
      }

      Future<String> wonderSwan(String orientation) => configFor(
        'wsc',
        'mednafen_wswan',
        'Beetle WonderSwan',
        'wswan_rotate_display = "$orientation"',
        'pegasus/wswanc',
        'Game.wsc',
      );
      Future<String> ds(String layout) => configFor(
        'ds',
        'melonds',
        'melonDS',
        'melonds_screen_gap = "0"\nmelonds_screen_layout = "$layout"',
        'pegasus/ds',
        'Game.nds',
      );

      Future<String> modernDs(
        int count, {
        int gap = 0,
        String layout = 'left-right',
      }) => configFor(
        'ds',
        'melondsds',
        'melonDS DS',
        'melonds_screen_gap = "$gap"\n'
            'melonds_number_of_screen_layouts = "$count"\n'
            'melonds_screen_layout1 = "$layout"',
        'pegasus/ds',
        'Game.nds',
      );

      Future<String> citra(String layout) => configFor(
        '3ds',
        'citra',
        'Citra',
        'citra_layout_option = "$layout"',
        'pegasus/3ds',
        'Game.3ds',
      );

      double aspect(String config) {
        int dimension(String key) =>
            int.parse(RegExp('$key = "(\\d+)"').firstMatch(config)!.group(1)!);
        return dimension('custom_viewport_width') /
            dimension('custom_viewport_height');
      }

      expect(aspect(await wonderSwan('portrait')), closeTo(9 / 14, .005));
      expect(await wonderSwan('manual'), isNot(contains('input_overlay =')));
      expect(aspect(await ds('Top/Bottom')), closeTo(2 / 3, .005));
      expect(aspect(await ds('Left/Right')), closeTo(8 / 3, .02));
      expect(await ds('Hybrid Bottom'), isNot(contains('input_overlay =')));
      expect(
        await RetroArchVisualSession.previewBorderGeometry(
          system: 'ds',
          coreFilename: 'melonds_libretro.so',
        ),
        isNull,
      );
      expect(aspect(await modernDs(1)), closeTo(8 / 3, .02));
      expect(await modernDs(2), isNot(contains('input_overlay =')));
      expect(
        aspect(await modernDs(1, gap: 100, layout: 'top-bottom')),
        closeTo(256 / 484, .005),
      );
      expect(await modernDs(1, gap: 100), isNot(contains('input_overlay =')));

      expect(
        aspect(await citra('Default Top-Bottom Screen')),
        closeTo(5 / 6, .005),
      );
      expect(aspect(await citra('Side by Side')), closeTo(3, .02));
      expect(
        aspect(await citra('Large Screen, Small Screen')),
        closeTo(2, .02),
      );
      expect(
        await citra('Single Screen Only'),
        isNot(contains('input_overlay =')),
      );
    },
    skip: !Platform.isLinux,
  );
}
