import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/artwork_preview.dart';
import '../models/rom_fingerprint.dart';
import '../models/system_family.dart';
import '../utils/app_config.dart';
import '../utils/semaphore.dart';
import 'logger_service.dart';

/// One credential-gated NeoAssets lookup shared by an individual ROM's
/// artwork categories and metadata import.
class NeoAssetsGameService {
  NeoAssetsGameService(
    this.systemId,
    this.title, {
    this.fingerprint,
    this.shouldCancel,
    this.allowPartialMatch = false,
    this.client,
    this.credentials,
  });

  final String systemId;
  final String title;
  final Future<RomFingerprint?> Function()? fingerprint;
  final bool Function()? shouldCancel;
  final bool allowPartialMatch;
  final http.Client? client;
  final ({String id, String secret, String? userKey})? credentials;

  static final _log = LoggerService.instance;
  static final _lookupSlots = Semaphore(1);
  static DateTime? _retryAfter;
  static const _timeout = Duration(seconds: 12);
  static const _maxImageBytes = 16 * 1024 * 1024;

  // Values supported by the image picker and the automatic image store.
  static const imageKinds = {
    'cover': 'box2d',
    'boxfront': 'box2d',
    'screenshot': 'screenshots',
    'fanart': 'fanarts',
    'logo': 'wheels',
  };

  late final _game = _lookup();
  final _images = <String, Future<List<ArtworkPreview>>>{};
  final _failures = <String?>{};

  bool failedFor(String category) =>
      imageKinds.containsValue(category) &&
      (_failures.contains(null) || _failures.contains(category));

  bool get _cancelled => shouldCancel?.call() ?? false;

  static String _normalizeName(String value) => value
      .toLowerCase()
      .replaceFirst(RegExp(r'(?:\s+\([^)]*\)|\s*\[[^\]]*\])+\s*$'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  Future<Map<String, dynamic>?> _lookup() async {
    final id = credentials?.id ?? Platform.environment['NEOASSETS_CLIENT_ID'];
    final secret =
        credentials?.secret ?? Platform.environment['NEOASSETS_CLIENT_SECRET'];
    final userKey =
        credentials?.userKey ?? Platform.environment['NEOASSETS_USER_API_KEY'];
    final name = title.trim();
    if (id == null ||
        id.isEmpty ||
        secret == null ||
        secret.isEmpty ||
        name.isEmpty ||
        _cancelled) {
      return null;
    }
    final parent = parentSystemId(systemId);
    await _lookupSlots.acquire();
    try {
      if (_cancelled) return null;
      if (_retryAfter?.isAfter(DateTime.now()) ?? false) {
        _failures.add(null);
        return null;
      }
      final hashes = await fingerprint?.call();
      if (_cancelled) return null;
      final uri =
          Uri.parse('${AppConfig.neoAssetsApiBaseUrl}/api/v1/scrape/games')
              .replace(
                queryParameters: {
                  'system_id': parent,
                  'name': name,
                  if (parent != systemId) 'type': 'hack',
                  if (hashes?.md5 case final String md5) 'md5': md5,
                  if (hashes != null && hashes.crc32.isNotEmpty)
                    'crc': hashes.crc32,
                  'media': imageKinds.keys.join(','),
                },
              );
      final response = await _get(
        uri,
        headers: {
          'X-Client-Id': id,
          'X-Client-Secret': secret,
          if (userKey != null && userKey.isNotEmpty)
            'Authorization': 'Bearer $userKey',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode != 200) {
        if (const {401, 403, 429, 503}.contains(response.statusCode)) {
          final seconds =
              int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
          final now = DateTime.now();
          final quotaReset = response.headers['x-quota-remaining'] == '0'
              ? DateTime.tryParse(response.headers['x-quota-reset'] ?? '')
              : null;
          _retryAfter = quotaReset != null && quotaReset.isAfter(now)
              ? quotaReset
              : now.add(Duration(seconds: seconds.clamp(1, 86400)));
        }
        _failures.add(null);
        _log.w('NeoAssets game lookup HTTP ${response.statusCode}');
        return null;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map || !body.containsKey('game')) {
        throw const FormatException('Invalid NeoAssets game response');
      }
      final game = body['game'];
      if (game == null || _cancelled) return null;
      if (game is! Map<String, dynamic> ||
          game['system_id'] != parent ||
          game['name'] is! String) {
        return null;
      }
      if (!allowPartialMatch &&
          body['matched_by'] != 'hash' &&
          _normalizeName(game['name'] as String) != _normalizeName(name)) {
        return null;
      }
      return game;
    } catch (error) {
      _failures.add(null);
      _log.w('NeoAssets game lookup failed (${error.runtimeType})');
      return null;
    } finally {
      _lookupSlots.release();
    }
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = 1024 * 1024,
  }) async {
    final active = client ?? http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final response = await active.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        return http.Response(
          '',
          response.statusCode,
          headers: response.headers,
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_timeout)) {
        if (_cancelled || bytes.length + chunk.length > maxBytes) {
          throw const FormatException(
            'NeoAssets response exceeds download limit',
          );
        }
        bytes.add(chunk);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
      );
    } finally {
      if (client == null) active.close();
    }
  }

  Future<List<ArtworkPreview>> inCategory(String category) =>
      _images.putIfAbsent(category, () => _loadImages(category));

  Future<List<ArtworkPreview>> _loadImages(String category) async {
    if (!imageKinds.containsValue(category) || _cancelled) return [];
    final game = await _game;
    final media = game?['media'];
    if (game == null || media is! List) return [];
    final result = <ArtworkPreview>[];
    final seen = <Uri>{};
    for (final asset in media.whereType<Map>()) {
      if (_cancelled) break;
      if (imageKinds[asset['kind']] != category ||
          asset['mime'] is! String ||
          !(asset['mime'] as String).startsWith('image/') ||
          (asset['size'] is int && (asset['size'] as int) > _maxImageBytes)) {
        continue;
      }
      final uri = Uri.tryParse(asset['url']?.toString() ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != Uri.parse(AppConfig.neoAssetsCdnBaseUrl).host ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !seen.add(uri)) {
        continue;
      }
      try {
        final response = await _get(uri, maxBytes: _maxImageBytes);
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          if (response.statusCode != 404) _failures.add(category);
          continue;
        }
        result.add((
          provider: ArtworkProvider.neoAssets,
          category: category,
          title: game['name'] as String,
          bytes: response.bodyBytes,
        ));
      } catch (error) {
        _failures.add(category);
        _log.w('NeoAssets image request failed (${error.runtimeType})');
      }
    }
    return result;
  }

  Future<Map<String, Object?>> metadata() async {
    final game = await _game;
    if (game == null || _cancelled) return {};
    final year = game['release_year'];
    return {
      'real_name': game['name'],
      for (final key in ['publisher', 'developer', 'genre'])
        if (game[key] case final String value when value.trim().isNotEmpty)
          key: value.trim(),
      if (year is int && year >= 1900 && year <= 2100)
        'release_date': '$year-01-01',
      for (final lang in ['en', 'fr', 'es', 'de', 'pt', 'it', 'jp'])
        if (game['description_$lang'] case final String description
            when description.trim().isNotEmpty)
          'description_$lang': description.trim(),
    };
  }
}
