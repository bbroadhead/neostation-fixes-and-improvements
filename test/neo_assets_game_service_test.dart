import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/models/artwork_preview.dart';
import 'package:neostation/models/rom_fingerprint.dart';
import 'package:neostation/services/neo_assets_game_service.dart';

void main() {
  const credentials = (
    id: 'example-client',
    secret: 'example-secret',
    userKey: 'example-user',
  );
  const media = [
    {
      'kind': 'cover',
      'mime': 'image/png',
      'url': 'https://cdn.neoassets.dev/cover.png',
    },
    {
      'kind': 'manual',
      'mime': 'application/pdf',
      'url': 'https://cdn.neoassets.dev/manual.pdf',
    },
    {
      'kind': 'cover',
      'mime': 'image/png',
      'url': 'https://example.com/cover.png',
    },
    {
      'kind': 'logo',
      'mime': 'image/png',
      'url': 'https://cdn.neoassets.dev/logo.png',
    },
  ];
  String game(String title, {String matchedBy = 'name'}) => jsonEncode({
    'system_id': 'snes',
    'matched_by': matchedBy,
    'game': {
      'system_id': 'snes',
      'name': title,
      'developer': 'Example studio',
      'release_year': 1994,
      'description_en': 'Example description',
      'media': media,
    },
  });

  test('shares a hash-first parent lookup for media and metadata', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      expect(request.followRedirects, isFalse);
      if (request.url.host == 'api.neoassets.dev') {
        expect(request.url.path, '/api/v1/scrape/games');
        expect(request.url.queryParameters, containsPair('system_id', 'snes'));
        expect(request.url.queryParameters, containsPair('type', 'hack'));
        expect(request.url.queryParameters, containsPair('crc', 'ABCD1234'));
        expect(request.headers, containsPair('X-Client-Id', credentials.id));
        expect(
          request.headers,
          containsPair('X-Client-Secret', credentials.secret),
        );
        expect(
          request.headers,
          containsPair('Authorization', 'Bearer example-user'),
        );
        return http.Response(game('Verified title', matchedBy: 'hash'), 200);
      }
      expect(request.headers, isEmpty);
      expect(request.url.host, 'cdn.neoassets.dev');
      return http.Response.bytes([1, 2, 3], 200);
    });
    final source = NeoAssetsGameService(
      'snes-hacks',
      'ROM label',
      credentials: credentials,
      client: client,
      fingerprint: () async =>
          const RomFingerprint(crc32: 'ABCD1234', sizeBytes: 1),
    );
    final cover = await source.inCategory('box2d');
    expect(cover.single.provider, ArtworkProvider.neoAssets);
    expect(await source.inCategory('box2d'), cover);
    expect((await source.inCategory('wheels')).single.title, 'Verified title');
    expect(await source.inCategory('manuals'), isEmpty);
    expect(await source.metadata(), {
      'real_name': 'Verified title',
      'developer': 'Example studio',
      'release_date': '1994-01-01',
      'description_en': 'Example description',
    });
    expect(requests.map((uri) => uri.path), [
      '/api/v1/scrape/games',
      '/cover.png',
      '/logo.png',
    ]);
  });

  test(
    'manual title search can see a close title rejected on auto-import',
    () async {
      final client = MockClient(
        (request) async => request.url.host == 'api.neoassets.dev'
            ? http.Response(game('Example Adventure'), 200)
            : http.Response.bytes([1], 200),
      );
      final automatic = NeoAssetsGameService(
        'snes',
        'Example',
        credentials: credentials,
        client: client,
      );
      final manual = NeoAssetsGameService(
        'snes',
        'Example',
        credentials: credentials,
        client: client,
        allowPartialMatch: true,
      );
      expect(await automatic.inCategory('box2d'), isEmpty);
      expect(await automatic.metadata(), isEmpty);
      expect(await manual.inCategory('box2d'), hasLength(1));
    },
  );

  test(
    'absent developer credentials leave all providers able to fall back',
    () async {
      final source = NeoAssetsGameService(
        'snes',
        'Example',
        credentials: (id: '', secret: '', userKey: null),
        client: MockClient((_) async => throw StateError('Unexpected request')),
      );
      expect(await source.inCategory('box2d'), isEmpty);
      expect(source.failedFor('box2d'), isFalse);
    },
  );
}
