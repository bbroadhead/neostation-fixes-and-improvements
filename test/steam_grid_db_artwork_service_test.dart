import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/models/artwork_preview.dart';
import 'package:neostation/services/steam_grid_db_artwork_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'artwork requests use the persisted key without an explicit key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      await SteamGridDbArtworkService.saveApiKey('  saved-key  ');
      var requested = false;
      final client = MockClient((request) async {
        requested = true;
        expect(request.headers['authorization'], 'Bearer saved-key');
        return http.Response('{"success":true,"data":[]}', 200);
      });
      addTearDown(client.close);

      await SteamGridDbArtworkService(
        'A Game',
        client: client,
      ).inCategory('icons');
      expect(requested, isTrue);
    },
  );

  test(
    'matches once, selects portrait covers and keeps credentials off the CDN',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        final uri = request.url;
        requests.add(uri);
        if (uri.host == 'cdn.steamgriddb.com') {
          expect(request.headers['authorization'], isNull);
          return http.Response.bytes([1, 2, 3], 200);
        }
        expect(uri.host, 'www.steamgriddb.com');
        expect(request.headers['authorization'], 'Bearer fixture-key');
        switch (Uri.decodeComponent(uri.path)) {
          case '/api/v2/search/autocomplete/A Game':
            return http.Response(
              jsonEncode({
                'success': true,
                'data': [
                  {'name': 'A Game 2', 'id': 2},
                  {'name': 'A Game', 'id': 1},
                ],
              }),
              200,
            );
          case '/api/v2/grids/game/1':
            return http.Response(
              jsonEncode({
                'success': true,
                'data': [
                  {
                    'url': 'https://cdn.steamgriddb.com/wide.jpg',
                    'width': 600,
                    'height': 400,
                    'mime': 'image/jpeg',
                  },
                  {
                    'url': 'https://cdn.steamgriddb.com/portrait.jpg',
                    'width': 400,
                    'height': 600,
                    'mime': 'image/jpeg',
                  },
                ],
              }),
              200,
            );
          default:
            return http.Response('{"success":true,"data":[]}', 200);
        }
      });
      final provider = SteamGridDbArtworkService(
        'A Game (USA, Europe) (Rev 1)',
        apiKey: 'fixture-key',
        client: client,
      );
      final covers = await provider.inCategory('box2d');
      expect(covers.single.provider, ArtworkProvider.steamGridDb);
      expect(covers.single.category, 'box2d');
      expect(await provider.inCategory('screenshots'), isEmpty);
      expect(await provider.inCategory('icons'), isEmpty);
      expect(requests.map((uri) => Uri.decodeComponent(uri.path)), [
        '/api/v2/search/autocomplete/A Game',
        '/api/v2/grids/game/1',
        '/portrait.jpg',
        '/api/v2/icons/game/1',
      ]);
      client.close();
    },
  );
}
