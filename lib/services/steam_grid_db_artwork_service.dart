import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/artwork_preview.dart';
import 'logger_service.dart';
import 'screenscraper/screenscraper_client.dart';

/// A title lookup shared by all categories of one scraping request.
class SteamGridDbArtworkService {
  SteamGridDbArtworkService(
    this.title, {
    this.shouldCancel,
    this.onFailure,
    this.allowPartialMatch = false,
    String? apiKey,
    this.client,
  }) : _key = (apiKey ?? Platform.environment['STEAMGRIDDB_API_KEY'] ?? '')
           .trim();

  final String title;
  final bool allowPartialMatch;
  final bool Function()? shouldCancel;
  final void Function(String? category)? onFailure;
  late final _game = _findGame();
  static final _log = LoggerService.instance;

  // Read at runtime so the build and Git repository never contain the key.
  final String _key;
  final http.Client? client;

  static const endpoints = {
    'box2d': 'grids',
    'fanarts': 'heroes',
    'wheels': 'logos',
    'icons': 'icons',
  };

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    final client = this.client;
    return client != null
        ? client.get(uri, headers: headers)
        : ScreenscraperClient.httpGetWithRetry(
            uri,
            headers: headers,
            shouldCancel: shouldCancel,
            timeout: const Duration(seconds: 10),
          );
  }

  Future<List<dynamic>> _request(List<String> segments) async {
    if (shouldCancel?.call() ?? false) return [];
    final response = await _get(
      Uri(
        scheme: 'https',
        host: 'www.steamgriddb.com',
        pathSegments: ['api', 'v2', ...segments],
      ),
      headers: {'Authorization': 'Bearer $_key', 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw HttpException('SteamGridDB HTTP ${response.statusCode}');
    }
    final result = jsonDecode(response.body);
    if (result is! Map ||
        result['success'] != true ||
        result['data'] is! List) {
      throw const FormatException('Invalid SteamGridDB response');
    }
    return result['data'] as List;
  }

  static final _dumpSuffix = RegExp(
    r'(?:\s+\((?:(?:USA|Europe|Japan|World|Australia|Canada|Korea|China|Brazil)(?:, (?:USA|Europe|Japan|World|Australia|Canada|Korea|China|Brazil))*|Rev [0-9A-Z.]+)\))+$',
    caseSensitive: false,
  );

  Future<({int id, String name})?> _findGame() async {
    final searchTitle = title.trim().replaceFirst(_dumpSuffix, '').trim();
    if (_key.isEmpty || searchTitle.isEmpty) return null;
    try {
      final query = searchTitle.toLowerCase();
      final entries = await _request(['search', 'autocomplete', searchTitle]);
      final matches = {
        for (final game in entries.whereType<Map>())
          if (game['id'] is int && game['name'] is String)
            (id: game['id'] as int, name: (game['name'] as String).trim()),
      };
      final exact = matches.where((game) => game.name.toLowerCase() == query);
      if (exact.length == 1) return exact.single;
      return allowPartialMatch
          ? (exact.firstOrNull ?? matches.firstOrNull)
          : null;
    } catch (error) {
      if (!(shouldCancel?.call() ?? false)) onFailure?.call(null);
      _log.w('SteamGridDB title lookup failed (${error.runtimeType})');
      return null;
    }
  }

  Future<List<ArtworkPreview>> inCategory(
    String category, {
    int limit = 3,
  }) async {
    final endpoint = endpoints[category];
    if (endpoint == null) return [];
    final game = await _game;
    if (game == null) return [];
    try {
      final assets =
          (await _request([endpoint, 'game', '${game.id}']))
              .whereType<Map>()
              .where(
                (asset) =>
                    asset['nsfw'] != true &&
                    asset['humor'] != true &&
                    asset['epilepsy'] != true &&
                    const {
                      'image/png',
                      'image/jpeg',
                      'image/webp',
                    }.contains(asset['mime']) &&
                    (category != 'box2d' ||
                        (asset['width'] is num &&
                            asset['height'] is num &&
                            (asset['height'] as num) >
                                (asset['width'] as num))),
              )
              .toList()
            ..sort(
              (a, b) => ((b['score'] as num?) ?? 0).compareTo(
                (a['score'] as num?) ?? 0,
              ),
            );
      final images = <ArtworkPreview>[];
      final seen = <Uri>{};
      for (final asset in assets) {
        if (images.length >= limit || (shouldCancel?.call() ?? false)) break;
        final uri = Uri.tryParse(asset['url']?.toString() ?? '');
        if (uri == null ||
            uri.scheme != 'https' ||
            !const {
              'cdn.cloudflare.steamstatic.com',
              'cdn.steamgriddb.com',
            }.contains(uri.host) ||
            uri.userInfo.isNotEmpty ||
            !seen.add(uri)) {
          continue;
        }
        try {
          final response = await _get(uri);
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            images.add((
              provider: ArtworkProvider.steamGridDb,
              category: category,
              title: game.name,
              bytes: response.bodyBytes,
            ));
          } else if (response.statusCode != 404) {
            onFailure?.call(category);
          }
        } catch (error) {
          if (!(shouldCancel?.call() ?? false)) onFailure?.call(category);
          _log.w('SteamGridDB asset failed (${error.runtimeType})');
        }
      }
      return images;
    } catch (error) {
      if (!(shouldCancel?.call() ?? false)) onFailure?.call(category);
      _log.w('SteamGridDB $category lookup failed (${error.runtimeType})');
      return [];
    }
  }
}
