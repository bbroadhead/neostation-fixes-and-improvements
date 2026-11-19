import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/libretro_thumbnail_service.dart';
import 'package:neostation/services/screenscraper/media_resolver.dart';

import 'database_test_helper.dart';

void main() {
  final db = DatabaseTestHelper();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2x8AAAAASUVORK5CYII=',
  );
  late Directory media;
  late HttpServer server;
  late List<List<String>> hits;
  late bool serveImage;

  setUp(() async {
    await db.setUp();
    media = await Directory.systemTemp.createTemp('libretro_artwork_');
    ScreenscraperMediaResolver.setMediaDirectoryForTesting(media.path);
    hits = [];
    serveImage = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      hits.add(request.uri.pathSegments);
      if (serveImage &&
          request.uri.pathSegments.last == 'Game _ Watch (USA).png') {
        request.response.add(png);
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

  Future<bool> download({String appSystemId = 'nes', bool force = false}) =>
      LibretroThumbnailService.download(
        appSystemId: appSystemId,
        systemFolder: 'nes',
        romName: 'Game & Watch (USA).nes',
        enabledMediaTypes: ['box2D', 'video'],
        forceOverwrite: force,
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

  test('an unsupported system sends no request', () async {
    expect(await download(appSystemId: 'android'), isFalse);
    expect(hits, isEmpty);
  });

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
