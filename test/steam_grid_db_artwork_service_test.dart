import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/models/artwork_preview.dart';
import 'package:neostation/services/steam_grid_db_artwork_service.dart';
import 'package:neostation/services/credential_file_store.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );

  test('successful lookup validates the trimmed Bearer key', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer fixture-key');
      expect(request.url.pathSegments, [
        'api',
        'v2',
        'search',
        'autocomplete',
        'Portal 2',
      ]);
      return http.Response(
        '{"success":true,"data":[{"name":"Portal 2","id":17830}]}',
        200,
      );
    });
    addTearDown(client.close);
    expect(
      await SteamGridDbArtworkService.testConnection(
        ' fixture-key ',
        client: client,
      ),
      isNull,
    );
  });

  for (final (status, failure) in [
    (401, SteamGridDbConnectionFailure.invalidKey),
    (403, SteamGridDbConnectionFailure.invalidKey),
    (429, SteamGridDbConnectionFailure.rateLimited),
    (500, SteamGridDbConnectionFailure.unavailable),
    (503, SteamGridDbConnectionFailure.unavailable),
    (200, SteamGridDbConnectionFailure.unexpectedResponse),
  ]) {
    test(
      'invalid connection response HTTP $status is reported safely',
      () async {
        final client = MockClient(
          (_) async => http.Response('<html>unexpected</html>', status),
        );
        addTearDown(client.close);
        expect(
          await SteamGridDbArtworkService.testConnection(
            'fixture-key',
            client: client,
          ),
          failure,
        );
      },
    );
  }

  for (final error in [
    TimeoutException('timed out'),
    const SocketException('offline'),
  ]) {
    test('reports ${error.runtimeType} as a network failure', () async {
      final client = MockClient((_) async => throw error);
      addTearDown(client.close);
      expect(
        await SteamGridDbArtworkService.testConnection(
          'fixture-key',
          client: client,
        ),
        SteamGridDbConnectionFailure.network,
      );
    });
  }

  test(
    'artwork requests use the persisted key without an explicit key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'steamgriddb-key-',
      );
      addTearDown(() => directory.delete(recursive: true));
      addTearDown(CredentialStore.debugReset);
      void openStore() => CredentialStore.debugUseBackends(
        preferEncryptedFile: true,
        file: CredentialFileStore(directory.path),
      );

      openStore();
      await SteamGridDbArtworkService.saveApiKey('  saved-key  ');
      openStore();
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
    'resolves a regional catalogue name without selecting the remake',
    () async {
      final client = MockClient((request) async {
        final name = request.url.pathSegments.last;
        final results = switch (name) {
          "Dragon Quest Monsters 2: Tara's Adventure" => [
            {
              'id': 5358768,
              'name': "Dragon Quest Monsters 2: Iru and Luca's Marvelous Mysterious Key",
            },
          ],
          "Dragon Warrior Monsters 2: Tara's Adventure" => [
            {
              'id': 36819,
              'name': "Dragon Warrior Monsters 2: Tara's Adventure",
            },
          ],
          _ => <Map<String, Object>>[],
        };
        if (request.url.pathSegments.contains('logos')) {
          expect(name, '36819');
          return http.Response(
            '{"success":true,"data":[{"url":"https://cdn.steamgriddb.com/logo.png","mime":"image/png"}]}',
            200,
          );
        }
        if (request.url.host == 'cdn.steamgriddb.com') {
          return http.Response.bytes(png, 200);
        }
        return http.Response(
          jsonEncode({'success': true, 'data': results}),
          200,
        );
      });
      addTearDown(client.close);
      final provider = SteamGridDbArtworkService(
        "Dragon Quest Monsters 2: Tara's Adventure",
        apiKey: 'fixture-key',
        client: client,
        allowPartialMatch: true,
      );
      expect((await provider.inCategory('wheels')).single.category, 'wheels');
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
          return http.Response.bytes(png, 200);
        }
        expect(uri.host, 'www.steamgriddb.com');
        expect(request.headers['authorization'], 'Bearer fixture-key');
        switch (Uri.decodeComponent(uri.path)) {
          case '/api/v2/search/autocomplete/Provider Alias':
            return http.Response('{"success":false}', 404);
          case '/api/v2/search/autocomplete/Super Mario World':
            return http.Response(
              jsonEncode({
                'success': true,
                'data': [
                  {'name': 'Super Mario World 2', 'id': 2},
                  {'name': 'Super Mario World', 'id': 36886},
                ],
              }),
              200,
            );
          case '/api/v2/grids/game/36886':
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
        'Provider Alias',
        alternateTitle: 'Super Mario World (USA, Europe) (Rev 1)',
        apiKey: 'fixture-key',
        client: client,
      );
      final covers = await provider.inCategory('box2d');
      expect(covers.single.provider, ArtworkProvider.steamGridDb);
      expect(covers.single.category, 'box2d');
      expect(await provider.inCategory('screenshots'), isEmpty);
      expect(await provider.inCategory('icons'), isEmpty);
      expect(requests.map((uri) => Uri.decodeComponent(uri.path)), [
        '/api/v2/search/autocomplete/Provider Alias',
        '/api/v2/search/autocomplete/Super Mario World',
        '/api/v2/grids/game/36886',
        '/portrait.jpg',
        '/api/v2/icons/game/36886',
      ]);
      client.close();
    },
  );
}
