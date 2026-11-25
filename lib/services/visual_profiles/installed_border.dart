import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart'
    show AssetImage, FileImage, ImageProvider;
import 'package:path/path.dart' as path;

import 'gameplay_viewport.dart';

const deckDisplay = (width: 1280, height: 800);

/// An existing, decorative RetroArch overlay from its installed Borders pack.
class InstalledBorder {
  const InstalledBorder._(
    this.id,
    this.image,
    this.source,
    this.name, {
    this.configuredOpening,
    this.portrait,
    this.combinedScreens = false,
    this.stackedDs = false,
    this.zoomed = false,
    this.asset,
    this.imageSize,
    this.layoutAspect,
  });

  final PixelRect? configuredOpening;
  final bool? portrait;
  final bool combinedScreens;
  final bool stackedDs;
  final bool zoomed;
  final double? layoutAspect;

  bool supportsAspect(double aspect) =>
      (portrait == null || portrait == (aspect < 1)) &&
      (layoutAspect == null || (layoutAspect! - aspect).abs() < 0.001);
  static const _maxImageBytes = 16 * 1024 * 1024;

  final String id;
  final File? image;
  final String? asset;
  final ({int width, int height})? imageSize;
  ImageProvider get thumbnail =>
      asset == null ? FileImage(image!) : AssetImage(asset!);
  final String source;

  final String name;

  static Directory _customDirectory(String root, String system) =>
      Directory(path.join(root, 'neostation-borders', system));

  /// Validate the exact bytes that will be stored before exposing the border
  /// to the picker. The content hash gives duplicate imports a stable ID.
  static Future<InstalledBorder?> importPng(
    String configRoot,
    String system,
    File original,
  ) async {
    final dimensions = geometry(system);
    if (dimensions == null ||
        path.extension(original.path).toLowerCase() != '.png') {
      return null;
    }
    final input = await original.open();
    final Uint8List bytes;
    try {
      bytes = await input.read(_maxImageBytes + 1);
    } finally {
      await input.close();
    }
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length || bytes.length > _maxImageBytes) {
      return null;
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    final digest = sha256.convert(bytes);
    final name = path
        .basenameWithoutExtension(original.path)
        .replaceAll(RegExp(r'[^a-zA-Z0-9 ._-]'), '_')
        .trim();
    final shortName = name.isEmpty
        ? 'Border'
        : name.substring(0, math.min(80, name.length));
    final filename = '$shortName--$digest.png';
    final directory = _customDirectory(configRoot, system);
    await directory.create(recursive: true);
    final scratch = await directory.createTemp('.import-');
    try {
      final staged = await File(path.join(scratch.path, filename))
          .writeAsBytes(bytes, flush: true);
      final candidate = _custom(staged, system);
      try {
        if (await candidate.render(dimensions.aspect) == null) return null;
      } catch (_) {
        return null;
      }
      final destination = path.join(directory.path, filename);
      return _custom(await staged.rename(destination), system);
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  static InstalledBorder _custom(File file, String system) {
    final key = path.basenameWithoutExtension(file.path);
    return InstalledBorder._(
      'custom/$key',
      file,
      'custom',
      key.substring(0, key.lastIndexOf('--')),
      layoutAspect: switch (_baseSystem(system)) {
        '3ds' => 5 / 6,
        'ds' => 8 / 3,
        _ => null,
      },
    );
  }

  bool matches(String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final searchable = '$name $source'.toLowerCase();
    return words.every(searchable.contains);
  }

  static const _televisionSystems = {
    '2600',
    '5200',
    '7800',
    '32x',
    '3do',
    'chf',
    'dc',
    'fc',
    'fds',
    'genesis',
    'intv',
    'jag',
    'jagcd',
    'mark3',
    'md',
    'megadrive',
    'n64',
    'neogeo',
    'nes',
    'pccd',
    'pce',
    'pcfx',
    'ps1',
    'sat',
    'scd',
    'sg1k',
    'sms',
    'snes',
  };

  static String _baseSystem(String system) => system.endsWith('-hacks')
      ? system.substring(0, system.length - '-hacks'.length)
      : system;

  static ({double aspect, int? nativeHeight})? geometry(String system) =>
      switch (_baseSystem(system)) {
        'gb' || 'gbc' => (aspect: 10 / 9, nativeHeight: 144),
        'gba' => (aspect: 3 / 2, nativeHeight: 160),
        'gamegear' || 'gg' => (aspect: 4 / 3, nativeHeight: 144),
        'ngp' || 'ngpc' => (aspect: 160 / 152, nativeHeight: 152),
        'duck' => (aspect: 10 / 9, nativeHeight: 144),
        'mini' => (aspect: 3 / 2, nativeHeight: 64),
        'wsv' => (aspect: 1, nativeHeight: 160),
        'lynx' => (aspect: 160 / 102, nativeHeight: 102),
        'psp' => (aspect: 16 / 9, nativeHeight: 272),
        'ws' || 'wsc' => (aspect: 14 / 9, nativeHeight: 144),
        'ds' => (aspect: 8 / 3, nativeHeight: 192),
        '3ds' => (aspect: 5 / 6, nativeHeight: 480),
        final system when _televisionSystems.contains(system) => (
          aspect: 4 / 3,
          nativeHeight: null,
        ),
        _ => null,
      };

  static bool _matchesSystem(String pack, String name, String system) {
    final slug = _baseSystem(system);
    if (pack != 'pegasus') {
      final prefix = name.toLowerCase().split('-').first;
      return switch (prefix) {
        'gb' => slug == 'gb' || slug == 'gbc',
        'a2600' => slug == '2600',
        'psx' => slug == 'ps1',
        'tv' => false,
        _ => slug == prefix,
      };
    }
    final alias = name.toLowerCase();
    return switch (alias) {
      'atari2600' => slug == '2600',
      'atari5200' => slug == '5200',
      'atari7800' => slug == '7800',
      'atarijaguar' => slug == 'jag' || slug == 'jagcd',
      'channelf' => slug == 'chf',
      'dreamcast' => slug == 'dc',
      'famicom' => slug == 'nes' || slug == 'fc' || slug == 'fds',
      'genesis' => slug == 'genesis' || slug == 'megadrive',
      'megadrive' => slug == 'genesis' || slug == 'megadrive' || slug == 'md',
      'gg' => slug == 'gg' || slug == 'gamegear',
      'intellivision' => slug == 'intv',
      'markiii' => slug == 'sms' || slug == 'mark3',
      'mastersystem' => slug == 'sms',
      'pcengine' || 'supergrafx' => slug == 'pce',
      'pcenginecd' => slug == 'pccd',
      'psx' => slug == 'ps1',
      'saturn' => slug == 'sat',
      'sega32x' => slug == '32x',
      'segacd' => slug == 'scd',
      'sg1000' => slug == 'sg1k',
      'wswanc' => slug == 'ws' || slug == 'wsc',
      'snes87' => slug == 'snes',
      _ => alias == slug,
    };
  }

  static Future<List<InstalledBorder>> discover(
    String configRoot,
    String system,
  ) async {
    if (geometry(system) == null) return [];
    final borders = _bundledBorders(_baseSystem(system));
    const packs = {
      'borders': 'RetroArch',
      'ctr/borders': 'RetroArch CTR',
      'pegasus': 'Pegasus',
    };
    for (final entry in packs.entries) {
      final pack = entry.key;
      final directory = Directory(path.join(configRoot, 'overlays', pack));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || path.extension(entity.path) != '.cfg') continue;
        final name = path.basenameWithoutExtension(entity.path);
        if (!_matchesSystem(pack, name, system)) continue;
        final border = await _read(
          entity,
          directory,
          pack == 'borders' ? name : '$pack/$name',
          entry.value,
        );
        if (border != null) borders.add(border);
      }
    }
    borders.addAll(await _handheldPack(configRoot, _baseSystem(system)));
    final custom = _customDirectory(configRoot, system);
    if (await custom.exists()) {
      await for (final file in custom.list(followLinks: false)) {
        if (file is File &&
            RegExp(r'^.{1,80}--[0-9a-f]{64}\.png$')
                .hasMatch(path.basename(file.path)) &&
            await file.length() <= _maxImageBytes) {
          borders.add(_custom(file, system));
        }
      }
    }
    return borders..sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  }

  static List<InstalledBorder> _bundledBorders(String system) {
    const germanTacos = {
      'n64': {
        '2560-1600-int-n64-1-bk-cl-bl': 'N64 Black',
        '2560-1600-int-n64-2-bk-cl-bl': 'Ultra 64 Black',
        '2560-1600-int-n64-3-bk-cl-bl': 'N64 Box Art',
      },
      'ps1': {
        '2560-1600-int-ps1-1-bk-cl-wh': 'PSX Black',
        '2560-1600-int-ps1-2-bk-cl-wh': 'PSX SCE Black',
        '2560-1600-int-ps1-3-bk-cl-wh': 'PSX SCE Black II',
      },
    };
    final dualScreenLayouts = switch (system) {
      'ds' => const [
        (id: 'ds-stacked', aspect: 2 / 3, width: 480, height: 720),
        (id: 'ds-wide', aspect: 8 / 3, width: 1152, height: 432),
      ],
      '3ds' => const [
        (id: '3ds-stacked', aspect: 5 / 6, width: 600, height: 720),
        (id: '3ds-wide', aspect: 3.0, width: 1152, height: 384),
        (id: '3ds-large', aspect: 2.0, width: 1152, height: 576),
      ],
      _ => const <({String id, double aspect, int width, int height})>[],
    };
    return [
      for (final entry in (germanTacos[system] ?? const {}).entries)
        InstalledBorder._(
          'germantacos/${entry.key}',
          null,
          'GermanTacos',
          entry.value,
          asset: 'assets/bezels/germantacos/${entry.key}.png',
          imageSize: (width: 2560, height: 1600),
          configuredOpening: (x: 340, y: 101, width: 1880, height: 1398),
        ),
      for (final layout in dualScreenLayouts)
        InstalledBorder._(
          'neostation/${layout.id}',
          null,
          'NeoStation',
          'Graphite',
          asset: 'assets/bezels/dual_screen/${layout.id}.png',
          imageSize: deckDisplay,
          configuredOpening: (
            x: (deckDisplay.width - layout.width) ~/ 2,
            y: (deckDisplay.height - layout.height) ~/ 2,
            width: layout.width,
            height: layout.height,
          ),
          layoutAspect: layout.aspect,
        ),
    ];
  }

  static const _handheldFolders = {
    'lynx': 'Atari Lynx',
    'duck': 'Creatronic Mega Duck',
    'mini': 'Nintendo Pokemon Mini',
    'wsv': 'Watara Supervision',
    'ws': 'Bandai WonderSwan',
    'wsc': 'Bandai WonderSwan Color',
    '3ds': 'Nintendo 3DS',
    'ds': 'Nintendo DS',
    'gb': 'Nintendo Game Boy',
    'gba': 'Nintendo Game Boy Advance',
    'gbc': 'Nintendo Game Boy Color',
    'ngp': 'SNK Neo Geo Pocket',
    'ngpc': 'SNK Neo Geo Pocket Color',
    'gg': 'Sega Game Gear',
    'gamegear': 'Sega Game Gear',
    'psp': 'Sony PSP',
  };

  static Future<List<InstalledBorder>> _handheldPack(
    String configRoot,
    String system,
  ) async {
    final folder = _handheldFolders[system];
    if (folder == null) return [];
    final directory = Directory(
      path.join(
        configRoot,
        'neostation-border-packs',
        'handheld-2.1.0',
        folder,
      ),
    );
    final result = <InstalledBorder>[];
    final seen = <Digest>{};
    try {
      if (!await directory.exists()) return result;
      final entries = await directory
          .list(recursive: true, followLinks: false)
          .where(
            (entry) => entry is File && path.extension(entry.path) == '.png',
          )
          .cast<File>()
          .toList();
      entries.sort((a, b) => a.path.compareTo(b.path));
      for (final image in entries) {
        try {
          final ini = File(path.setExtension(image.path, '.ini'));
          if (await FileSystemEntity.type(ini.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              await ini.length() > 16384 ||
              await image.length() > _maxImageBytes) {
            continue;
          }
          final opening = _rocketLauncherOpening(await ini.readAsString());
          if (opening == null) continue;
          final digest = await sha256.bind(image.openRead()).first;
          if (!seen.add(digest)) continue;
          final name = path.basenameWithoutExtension(image.path);
          final relativePath = path.relative(image.path, from: directory.path);
          final orientation = path.split(relativePath);
          final border = InstalledBorder._(
            'handheld-2.1.0/$folder/$relativePath',
            image,
            'ci2own · Handheld Bezels 2.1.0',
            name.replaceFirst(RegExp('^Bezel '), ''),
            configuredOpening: opening,
            portrait: orientation.contains('Vertical')
                ? true
                : orientation.contains('Horizontal')
                ? false
                : null,
            combinedScreens: system == 'ds' || system == '3ds',
            stackedDs: system == 'ds',
          );
          result.add(border);
          if (!border.combinedScreens) {
            result.add(
              InstalledBorder._(
                '${border.id}#zoom',
                image,
                border.source,
                border.name,
                configuredOpening: opening,
                portrait: border.portrait,
                zoomed: true,
              ),
            );
          }
        } on FileSystemException {
          continue;
        } on FormatException {
          continue;
        }
      }
    } on FileSystemException {
      return result;
    }
    return result;
  }

  static PixelRect? _rocketLauncherOpening(String ini) {
    final coordinates = <String, int>{};
    final lines = RegExp(
      r'^Bezel Screen (Top Left|Bottom Right) ([XY]) Coordinate\s*=\s*(\d+)[ \t]*\r?$',
      multiLine: true,
    );
    for (final match in lines.allMatches(ini)) {
      final value = int.tryParse(match[3]!);
      if (value != null) coordinates['${match[1]}${match[2]}'] = value;
    }
    final x = coordinates['Top LeftX'];
    final y = coordinates['Top LeftY'];
    final right = coordinates['Bottom RightX'];
    final bottom = coordinates['Bottom RightY'];
    if (x == null ||
        y == null ||
        right == null ||
        bottom == null ||
        right <= x ||
        bottom <= y) {
      return null;
    }
    return (x: x, y: y, width: right - x, height: bottom - y);
  }

  static Future<InstalledBorder?> _read(
    File cfg,
    Directory directory,
    String id,
    String source,
  ) async {
    try {
      if (await cfg.length() > 16384) return null;
      final settings = <String, String>{};
      for (final line in await cfg.readAsLines()) {
        final separator = line.indexOf('=');
        if (separator < 0) continue;
        settings[line.substring(0, separator).trim()] = line
            .substring(separator + 1)
            .trim()
            .replaceAll('"', '');
      }
      final overlay = settings['overlay0_overlay'];
      if (settings['overlays'] != '1' ||
          settings['overlay0_descs'] != '0' ||
          settings['overlay0_full_screen'] != 'true' ||
          overlay == null ||
          path.extension(overlay) != '.png' ||
          path.isAbsolute(overlay)) {
        return null;
      }
      final image = File(path.join(directory.path, overlay));
      if (!await image.exists() || await image.length() > _maxImageBytes) {
        return null;
      }
      final canonical = await image.resolveSymbolicLinks();
      if (!path.isWithin(await directory.resolveSymbolicLinks(), canonical)) {
        return null;
      }
      return InstalledBorder._(id, File(canonical), source, id.split('/').last);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<({PixelRect opening, Uint8List png})?> render(
    double aspect, {
    ({int width, int height}) display = deckDisplay,
  }) async {
    if (!supportsAspect(aspect) ||
        display.width < 3 ||
        display.height < 3 ||
        display.width > 4096 ||
        display.height > 4096) {
      return null;
    }
    final buffer = asset == null
        ? await ui.ImmutableBuffer.fromFilePath(image!.path)
        : await ui.ImmutableBuffer.fromAsset(asset!);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width > 4096 || descriptor.height > 4096) return null;
        if (imageSize != null &&
            imageSize != (width: descriptor.width, height: descriptor.height)) {
          return null;
        }
        final codec = await descriptor.instantiateCodec();
        try {
          if (codec.frameCount != 1) return null;
          final frame = (await codec.getNextFrame()).image;
          try {
            return await _fitArtwork(frame, aspect, display);
          } finally {
            frame.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  Future<({PixelRect opening, Uint8List png})?> _fitArtwork(
    ui.Image frame,
    double aspect,
    ({int width, int height}) display,
  ) async {
    PixelRect? sourceOpening;
    final gap = stackedDs && aspect.isFinite && aspect > 0
        ? (256 / aspect).round() - 384
        : 0;
    if (stackedDs && (gap < 1 || gap > 126)) return null;
    final configured = configuredOpening;
    if (configured != null) {
      if (configured.x + configured.width > frame.width ||
          configured.y + configured.height > frame.height) {
        return null;
      }
      final data = await frame.toByteData();
      if (data == null) return null;
      sourceOpening = stackedDs
          ? configured
          : transparentOpening(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              width: frame.width,
              height: frame.height,
              aspect: aspect,
              region: configured,
            );
      if (sourceOpening == null) return null;
      // A native combined framebuffer cannot span an opaque hinge. Require
      // the transparent rectangle to cover the declared screen region in both
      // dimensions, so one half cannot pass as the complete dual-screen area.
      if (combinedScreens &&
          !stackedDs &&
          (sourceOpening.height < configured.height * 0.85 ||
              sourceOpening.width < configured.width * 0.85 ||
              (sourceOpening.width / sourceOpening.height / aspect - 1).abs() >
                  0.2)) {
        return null;
      }
    }
    final cover = math.max(
      display.width / frame.width,
      display.height / frame.height,
    );
    var scale = cover;
    if (sourceOpening != null) {
      final maximum = math.min(
        display.width / sourceOpening.width,
        display.height / sourceOpening.height,
      );
      // Keep room for decorative housing and leave existing larger
      // openings with a single choice in the picker.
      if (zoomed && cover >= maximum * 0.5) return null;
      scale = math.min(zoomed ? maximum * 0.8 : cover, maximum);
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final width = frame.width * scale;
    final height = frame.height * scale;
    double offset(int available, double extent, int? start, int? length) {
      final center = zoomed && start != null && length != null
          ? (available / 2 - (start + length / 2) * scale)
                .clamp(
                  math.min(available - extent, 0.0),
                  math.max(available - extent, 0.0),
                )
                .toDouble()
          : (available - extent) / 2;
      if (start == null || length == null) return center;
      return center.clamp(
        -start * scale,
        math.max(-start * scale, available - (start + length) * scale),
      );
    }

    final left = offset(
      display.width,
      width,
      sourceOpening?.x,
      sourceOpening?.width,
    );
    final top = offset(
      display.height,
      height,
      sourceOpening?.y,
      sourceOpening?.height,
    );
    canvas.drawImageRect(
      frame,
      ui.Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      ui.Rect.fromLTWH(left, top, width, height),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(display.width, display.height);
      try {
        final data = await image.toByteData();
        if (data == null) return null;
        final rgba = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final region = sourceOpening == null
            ? null
            : (
                x: (left + sourceOpening.x * scale).ceil(),
                y: (top + sourceOpening.y * scale).ceil(),
                width: (sourceOpening.width * scale).floor() - 1,
                height: (sourceOpening.height * scale).floor() - 1,
              );
        final opening = stackedDs && region != null
            ? _stackedDsOpening(rgba, image.width, image.height, region, gap)
            : transparentOpening(
                rgba,
                width: image.width,
                height: image.height,
                aspect: aspect,
                region: region,
                preferVerticalRoom: source == 'custom' && aspect == 5 / 6,
              );
        if (opening == null) return null;
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return null;
        return (
          opening: opening,
          png: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  static PixelRect? _stackedDsOpening(
    Uint8List rgba,
    int width,
    int height,
    PixelRect region,
    int gap,
  ) {
    final half = region.height ~/ 2;
    PixelRect? screen(int y, int h) => transparentOpening(
      rgba,
      width: width,
      height: height,
      aspect: 4 / 3,
      region: (x: region.x, y: y, width: region.width, height: h),
    );
    final top = screen(region.y, half);
    final bottom = screen(region.y + half, region.height - half);
    if (top == null || bottom == null) return null;
    return GameplayViewport.fitStackedDs(top, bottom, gap);
  }

  /// Find the clear rectangle that can hold the largest complete frame.
  /// Each scan line contributes a histogram of contiguous transparent pixels.
  static PixelRect? transparentOpening(
    Uint8List rgba, {
    required int width,
    required int height,
    required double aspect,
    PixelRect? region,
    bool preferVerticalRoom = false,
  }) {
    if (width < 3 ||
        height < 3 ||
        rgba.length != width * height * 4 ||
        !aspect.isFinite ||
        aspect <= 0) {
      return null;
    }
    // Transparent pixels connected to the display edge are decorative
    // cutouts. Exclude them before looking for a screen opening.
    final outside = Uint8List(width * height);
    final queue = Int32List(width * height);
    var pending = 0;
    void add(int pixel) {
      if (outside[pixel] != 0 || rgba[pixel * 4 + 3] != 0) return;
      outside[pixel] = 1;
      queue[pending++] = pixel;
    }

    for (var x = 0; x < width; x++) {
      add(x);
      add((height - 1) * width + x);
    }
    for (var y = 1; y < height - 1; y++) {
      add(y * width);
      add(y * width + width - 1);
    }
    for (var i = 0; i < pending; i++) {
      final pixel = queue[i];
      final x = pixel % width;
      if (x > 0) add(pixel - 1);
      if (x < width - 1) add(pixel + 1);
      if (pixel >= width) add(pixel - width);
      if (pixel < outside.length - width) add(pixel + width);
    }

    final columns = List<int>.filled(width, 0);
    final stack = List<int>.filled(width, 0);
    PixelRect? best;
    var bestFrameHeight = 0.0;
    for (var y = 0; y < height; y++) {
      var count = 0;
      for (var x = 0; x <= width; x++) {
        final pixel = y * width + x;
        final current =
            x < width &&
                outside[pixel] == 0 &&
                rgba[pixel * 4 + 3] == 0 &&
                (region == null ||
                    (x >= region.x &&
                        x < region.x + region.width &&
                        y >= region.y &&
                        y < region.y + region.height))
            ? columns[x] + 1
            : 0;
        while (count > 0 && columns[stack[count - 1]] > current) {
          final h = columns[stack[--count]];
          final left = count == 0 ? 0 : stack[count - 1] + 1;
          final w = x - left;
          final fittedHeight = math.min(h.toDouble(), w / aspect);
          // A stacked frame can be width-limited. Keep the full height of
          // the same clear strip so its midpoint stays near the screen split.
          final extendsBestStrip =
              preferVerticalRoom &&
              best != null &&
              fittedHeight == bestFrameHeight &&
              left == best.x &&
              w == best.width &&
              y + 1 - h == best.y &&
              h > best.height;
          if (left > 0 &&
              x < width &&
              y + 1 > h &&
              y + 1 < height &&
              (fittedHeight > bestFrameHeight || extendsBestStrip)) {
            bestFrameHeight = fittedHeight;
            best = (x: left, y: y + 1 - h, width: w, height: h);
          }
        }
        if (x < width) {
          columns[x] = current;
          stack[count++] = x;
        }
      }
    }
    return best;
  }
}
