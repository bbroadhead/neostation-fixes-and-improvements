import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/visual_profiles/gameplay_viewport.dart';
import 'package:neostation/services/visual_profiles/installed_border.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const width = 16;
  const height = 10;

  Uint8List alpha(bool Function(int, int) clear) {
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        pixels[(y * width + x) * 4 + 3] = clear(x, y) ? 0 : 255;
      }
    }
    return pixels;
  }

  PixelRect? opening(Uint8List pixels, {double aspect = 3 / 2}) =>
      InstalledBorder.transparentOpening(
        pixels,
        width: width,
        height: height,
        aspect: aspect,
      );

  test('isolates the enclosed opening from transparent decorative edges', () {
    final pixels = alpha(
      (x, y) => x <= 2 || (x >= 4 && x < 13 && y >= 2 && y < 8),
    );
    expect(opening(pixels), (x: 4, y: 2, width: 9, height: 6));
  });

  test('retains vertical room for a width-limited stacked frame', () {
    final pixels = alpha(
      (x, y) => y >= 1 && y < 9 && x >= 5 && x < (y < 5 ? 12 : 10),
    );
    final bounds = InstalledBorder.transparentOpening(
      pixels,
      width: width,
      height: height,
      aspect: 5 / 6,
      preferVerticalRoom: true,
    );
    expect(bounds, (x: 5, y: 1, width: 5, height: 8));
    expect(GameplayViewport.fit(opening: bounds!, aspectRatio: 5 / 6), (
      x: 5,
      y: 2,
      width: 5,
      height: 6,
    ));
  });

  test('rejects completely empty, opaque and edge-only images', () {
    expect(opening(alpha((_, _) => true)), isNull);
    expect(opening(alpha((_, _) => false)), isNull);
    expect(opening(alpha((x, _) => x < 8)), isNull);
    expect(opening(alpha((x, y) => x > 1 && x < 12 && y > 2)), isNull);
  });

  test('keeps the frame clear of an opaque separator', () {
    final bounds = opening(
      alpha((x, y) => x > 1 && x < 14 && x != 8 && y > 1 && y < 8),
    )!;
    expect(bounds.x + bounds.width <= 8 || bounds.x > 8, isTrue);
  });
  test(
    'imports a validated PNG without using the original file at runtime',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'border-import-test-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final config = path.join(sandbox.path, 'retroarch');
      final original = File(path.join(sandbox.path, 'Pocket shell.png'));
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
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await original.writeAsBytes(bytes);
      image.dispose();
      picture.dispose();

      final first = (await InstalledBorder.importPng(config, 'gb', original))!;
      final duplicate = (await InstalledBorder.importPng(
        config,
        'gb',
        original,
      ))!;
      expect(duplicate.id, first.id);
      expect(first.name, 'Pocket shell');
      expect(first.matches('pocket custom'), isTrue);
      expect(first.matches('pegasus'), isFalse);

      await original.delete();
      final catalog = await InstalledBorder.discover(config, 'gb');
      expect(catalog.single.id, first.id);
      expect(await catalog.single.image!.exists(), isTrue);
      expect(await InstalledBorder.discover(config, 'gba'), isEmpty);
    },
  );

  test(
    'rejects a renamed text file without adding it to the catalog',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'invalid-border-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final fakePng = await File(path.join(root.path, 'bad.png'))
          .writeAsString('PNG');
      expect(await InstalledBorder.importPng(root.path, 'gb', fakePng), isNull);
      expect(await InstalledBorder.discover(root.path, 'gb'), isEmpty);
    },
  );
  test(
    'finds CTR and Pegasus variants using NeoStation system aliases',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'installed-packs-test-',
      );
      addTearDown(() => root.delete(recursive: true));

      Future<void> add(String pack, String name, {int controls = 0}) async {
        final folder = await Directory(path.join(root.path, 'overlays', pack))
            .create(recursive: true);
        await File(path.join(folder.path, '$name.png')).create();
        await File(path.join(folder.path, '$name.cfg')).writeAsString(
          'overlays = 1\noverlay0_overlay = $name.png\n'
          'overlay0_full_screen = true\noverlay0_descs = $controls\n',
        );
      }

      await add('borders', 'tv-integer');
      await add('ctr/borders', 'a2600-integer');
      await add('ctr/borders', 'psx-integer');
      await add('pegasus', 'Dreamcast');
      await add('pegasus', 'saturn');
      await add('pegasus', 'famicom');
      await add('pegasus', 'megadrive');
      await add('pegasus', 'MarkIII');
      await add('pegasus', 'atari2600', controls: 1);

      expect(
        (await InstalledBorder.discover(root.path, '2600')).single.id,
        'ctr/borders/a2600-integer',
      );
      expect(
        (await InstalledBorder.discover(
          root.path,
          'ps1-hacks',
        )).where((border) => border.source != 'GermanTacos').single.id,
        'ctr/borders/psx-integer',
      );
      expect(
        (await InstalledBorder.discover(root.path, 'dc')).single.id,
        'pegasus/Dreamcast',
      );
      expect(
        (await InstalledBorder.discover(root.path, 'sat')).single.id,
        'pegasus/saturn',
      );
      for (final entry in {
        'fc': 'famicom',
        'fds-hacks': 'famicom',
        'md': 'megadrive',
        'mark3': 'MarkIII',
      }.entries) {
        expect(
          (await InstalledBorder.discover(root.path, entry.key)).single.id,
          'pegasus/${entry.value}',
        );
      }
      expect(
        (await InstalledBorder.discover(
          root.path,
          'ds',
        )).where((border) => border.source != 'NeoStation'),
        isEmpty,
      );
    },
  );

  test('bundled N64 and PlayStation artwork fits the Deck display', () async {
    final root = await Directory.systemTemp.createTemp('bundled-border-test');
    addTearDown(() => root.delete(recursive: true));
    for (final system in ['n64', 'ps1']) {
      final borders = await InstalledBorder.discover(root.path, system);
      expect(borders, hasLength(3));
      for (final border in borders) {
        expect(border.source, 'GermanTacos');
        final rendered = await border.render(4 / 3);
        expect(rendered, isNotNull, reason: border.name);
        final viewport = GameplayViewport.fit(
          opening: rendered!.opening,
          aspectRatio: 4 / 3,
        );
        expect(viewport, isNotNull, reason: border.name);
        expect(viewport!.height, greaterThan(600), reason: border.name);
      }
    }
  });

  test('dual-screen bezels fit only their registered layout', () async {
    final root = await Directory.systemTemp.createTemp('dual-screen-test');
    addTearDown(() => root.delete(recursive: true));
    for (final (system, layouts) in [
      ('ds', [2 / 3, 8 / 3]),
      ('3ds', [5 / 6, 3.0, 2.0]),
    ]) {
      final borders = await InstalledBorder.discover(root.path, system);
      expect(borders, hasLength(layouts.length));
      for (final aspect in layouts) {
        final compatible = borders.singleWhere(
          (border) => border.supportsAspect(aspect),
        );
        expect(await compatible.render(aspect), isNotNull);
        for (final incompatible in layouts.where((other) => other != aspect)) {
          expect(await compatible.render(incompatible), isNull);
        }
      }
      expect(borders.any((border) => border.supportsAspect(4 / 3)), isFalse);
    }
  });

  test('RocketLauncher coordinates select the intended clear area', () async {
    final root = await Directory.systemTemp.createTemp('handheld-pack-test-');
    addTearDown(() => root.delete(recursive: true));
    final directory = await Directory(
      path.join(
        root.path,
        'neostation-border-packs',
        'handheld-2.1.0',
        'Nintendo Game Boy',
        '_Default',
      ),
    ).create(recursive: true);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src)
      ..drawRect(
        const ui.Rect.fromLTWH(30, 20, 40, 36),
        ui.Paint()..blendMode = ui.BlendMode.clear,
      )
      ..drawRect(
        const ui.Rect.fromLTWH(160, 15, 120, 108),
        ui.Paint()..blendMode = ui.BlendMode.clear,
      );
    final picture = recorder.endRecording();
    final image = await picture.toImage(300, 150);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    picture.dispose();
    for (final name in ['Bezel Handheld', 'Bezel Duplicate']) {
      await File(path.join(directory.path, '$name.png')).writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      await File(path.join(directory.path, '$name.ini')).writeAsString(
        '[General]\r\n'
        'Bezel Screen Top Left X Coordinate=30\r\n'
        'Bezel Screen Top Left Y Coordinate=20\r\n'
        'Bezel Screen Bottom Right X Coordinate=70\r\n'
        'Bezel Screen Bottom Right Y Coordinate=56\r\n',
      );
    }
    final borders = await InstalledBorder.discover(root.path, 'gb-hacks');
    final border = borders.singleWhere((border) => !border.zoomed);
    final zoomed = borders.singleWhere((border) => border.zoomed);
    expect(await InstalledBorder.discover(root.path, 'gbc'), isEmpty);
    expect(border.source, contains('ci2own'));
    final result = (await border.render(
      10 / 9,
      display: (width: 320, height: 200),
    ))!;
    expect(result.opening.x, lessThan(100));
    expect(result.opening.width, greaterThan(30));
    expect(result.opening.x + result.opening.width, lessThan(320));
    final enlarged = (await zoomed.render(
      10 / 9,
      display: (width: 320, height: 200),
    ))!;
    expect(zoomed.image!.path, border.image!.path);
    expect(enlarged.opening.height, greaterThan(result.opening.height * 2));
    final gameplay = GameplayViewport.fit(
      opening: enlarged.opening,
      aspectRatio: 10 / 9,
    )!;
    expect(gameplay.x, greaterThan(0));
    expect(gameplay.y, greaterThan(0));
    expect(gameplay.x + gameplay.width, lessThan(320));
    expect(gameplay.y + gameplay.height, lessThan(200));
  });
}
