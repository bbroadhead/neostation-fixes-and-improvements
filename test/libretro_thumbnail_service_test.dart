import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/libretro_thumbnail_service.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/services/screenscraper/media_resolver.dart';

import 'database_test_helper.dart';

void main() {
  final db = DatabaseTestHelper();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );
  late Directory media;
  late HttpServer server;
  late List<List<String>> hits;
  late bool serveImage;
  late bool serveTruncated;

  setUp(() async {
    await db.setUp();
    media = await Directory.systemTemp.createTemp('libretro_artwork_');
    ScreenscraperMediaResolver.setMediaDirectoryForTesting(media.path);
    hits = [];
    serveImage = true;
    serveTruncated = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      hits.add(request.uri.pathSegments);
      if (serveImage &&
          request.uri.pathSegments.last == 'Game _ Watch (USA).png') {
        request.response.add(serveTruncated ? png.sublist(0, 20) : png);
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    ScreenscraperMediaResolver.setMediaDirectoryForTesting(null);
    await media.delete(recursive: true);
    await db.tearDown();
  });

  Future<bool> download({
    String appSystemId = 'nes',
    bool force = false,
    String? romPath,
  }) => LibretroThumbnailService.download(
    appSystemId: appSystemId,
    systemFolder: 'nes',
    romName: 'Game & Watch (USA).nes',
    enabledMediaTypes: ['box2D', 'video'],
    forceOverwrite: force,
    romPath: romPath,
    catalog: Uri.parse('http://127.0.0.1:${server.port}'),
  );

  test(
    'downloads public box art, writes it to NeoStation, and reuses it',
    () async {
      expect(await download(), isTrue);
      expect(hits.single, [
        'Nintendo - Nintendo Entertainment System',
        'Named_Boxarts',
        'Game _ Watch (USA).png',
      ]);
      final art = File('${media.path}/nes/box2d/Game & Watch (USA).png');
      expect(await art.readAsBytes(), png);
      expect(await download(), isTrue);
      expect(hits, hasLength(1));
      serveImage = false;
      expect(await download(force: true), isTrue);
      expect(await art.readAsBytes(), png);
    },
  );

  test('a manual cover skips network downloads for the same slot', () async {
    const romPath = '/roms/nes/Game & Watch (USA).nes';
    final override = File(
      GameModel.artworkOverridePathForRom(
        romPath,
        'box2d',
        mediaDirectory: media.path,
      ),
    );
    await override.parent.create(recursive: true);
    await override.writeAsBytes(png);
    expect(await download(romPath: romPath), isTrue);
    expect(hits, isEmpty);
    expect(await override.readAsBytes(), png);
  });

  test('a truncated PNG is rejected before assignment', () async {
    serveTruncated = true;
    expect(await download(), isFalse);
    expect(await media.list().toList(), isEmpty);
  });

  test('an unsupported system sends no request', () async {
    expect(await download(appSystemId: 'android'), isFalse);
    expect(hits, isEmpty);
  });

  test(
    'the gallery returns available categories without changing local art',
    () async {
      final candidates = await LibretroThumbnailService.gallery(
        appSystemId: 'nes',
        romName: 'wrong-label.nes',
        gameName: 'Game & Watch (USA)',
        catalog: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      expect(candidates.map((item) => item.category), [
        'box2d',
        'screenshots',
        LibretroThumbnailService.titleScreens,
      ]);
      expect(
        candidates.every((item) => item.title == 'Game & Watch (USA)'),
        isTrue,
      );
      expect(await media.list().toList(), isEmpty);
      expect(hits, hasLength(6));
    },
  );

  test('a cover with a different file extension is retained', () async {
    final art = File('${media.path}/nes/box2d/Game & Watch (USA).jpg');
    await art.parent.create(recursive: true);
    await art.writeAsBytes(png);
    expect(await download(), isTrue);
    expect(hits, isEmpty);
    expect(await art.readAsBytes(), png);
  });

  test(
    'a search title changes the request and keeps the ROM artwork path',
    () async {
      expect(
        await LibretroThumbnailService.download(
          appSystemId: 'nes',
          systemFolder: 'nes',
          romName: 'my-cart.nes',
          enabledMediaTypes: ['box2D'],
          searchTitle: 'Game & Watch (USA)',
          catalog: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
        isTrue,
      );
      expect(hits.single.last, 'Game _ Watch (USA).png');
      expect(
        await File('${media.path}/nes/box2d/my-cart.png').readAsBytes(),
        png,
      );
    },
  );

  test('keeps title screens separate from gameplay and cover art', () async {
    Future<bool> downloadTitles() => LibretroThumbnailService.download(
      appSystemId: 'nes',
      systemFolder: 'nes',
      romName: 'Game & Watch (USA).nes',
      enabledMediaTypes: [LibretroThumbnailService.titleScreens],
      catalog: Uri.parse('http://127.0.0.1:${server.port}'),
    );

    expect(await downloadTitles(), isTrue);
    expect(hits.single[1], 'Named_Titles');
    expect(
      await File('${media.path}/nes/title_screens/Game & Watch (USA).png')
          .readAsBytes(),
      png,
    );
    expect(await Directory('${media.path}/nes/screenshots').exists(), isFalse);
    expect(await Directory('${media.path}/nes/box2d').exists(), isFalse);
    expect(await downloadTitles(), isTrue);
    expect(hits, hasLength(1));
  });
}
