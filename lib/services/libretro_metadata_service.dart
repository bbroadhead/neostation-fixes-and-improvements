import 'dart:convert';

import '../repositories/scraper_repository.dart';
import 'libretro_thumbnail_service.dart';
import 'logger_service.dart';
import 'screenscraper/rom_hasher.dart';
import 'screenscraper/screenscraper_client.dart';

/// A metadata catalog cache shared by the workers of one scrape.
class LibretroMetadataService {
  LibretroMetadataService({this.shouldCancel});

  final bool Function()? shouldCancel;

  static const _fields = {
    'developer': 'developer',
    'publisher': 'publisher',
    'genre': 'genre',
    'releaseyear': 'release_date',
  };

  final _catalogs = <String, Future<Map<String, Map<String, dynamic>>>>{};

  Future<bool> scrape(
    String systemId,
    String filename, {
    Map<String, Object?> verifiedMetadata = const {},
    String? searchTitle,
  }) async {
    final playlist = LibretroThumbnailService.playlistForSystem(systemId);
    if (playlist == null && verifiedMetadata.isEmpty) return false;
    final name =
        searchTitle ??
        await ScreenscraperRomHasher.getCleanRomName(filename, systemId);
    final catalog = playlist == null
        ? const <String, Map<String, dynamic>>{}
        : await _catalogs.putIfAbsent(playlist, () => _load(playlist));
    final fields = catalog[name.trim().toLowerCase()];
    if ((fields == null && verifiedMetadata.isEmpty) ||
        (shouldCancel?.call() ?? false)) {
      return false;
    }
    return ScraperRepository.fillGameMetadataGaps({
      'filename': filename,
      ...?fields,
      ...verifiedMetadata,
    }, systemId);
  }

  Future<Map<String, Map<String, dynamic>>> _load(String playlist) async {
    final categories = await Future.wait(
      _fields.keys.map((field) => _download(playlist, field)),
    );
    final catalog = <String, Map<String, dynamic>>{};
    for (final (index, category) in categories.indexed) {
      final field = _fields.keys.elementAt(index);
      for (final entry in category.entries) {
        final value = entry.value;
        if (field == 'releaseyear' && !RegExp(r'^\d{4}$').hasMatch(value)) {
          continue;
        }
        final record = catalog.putIfAbsent(entry.key, () => {});
        record[_fields[field]!] = field == 'releaseyear'
            ? '$value-01-01'
            : value;
      }
    }
    return catalog;
  }

  Future<Map<String, String>> _download(String playlist, String field) async {
    final url = Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [
        'libretro',
        'libretro-database',
        'master',
        'metadat',
        field,
        '$playlist.dat',
      ],
    );
    try {
      final response = await ScreenscraperClient.httpGetWithRetry(
        url,
        timeout: const Duration(seconds: 15),
        shouldCancel: shouldCancel,
      );
      if (response.statusCode == 200) {
        return parseDat(
          utf8.decode(response.bodyBytes, allowMalformed: true),
          field,
        );
      }
      if (response.statusCode != 404) {
        LoggerService.instance.w(
          'Libretro metadata HTTP ${response.statusCode}: $playlist / $field',
        );
      }
    } catch (error) {
      LoggerService.instance.w(
        'Libretro metadata unavailable: $playlist / $field (${error.runtimeType})',
      );
    }
    return {};
  }

  static Map<String, String> parseDat(String document, String field) {
    final games = RegExp(r'^game\s*\(([\s\S]*?)^\s*\)\s*$', multiLine: true);
    final name = RegExp(
      r'^\s*(?:comment|name)\s+"([^"\r\n]+)"',
      multiLine: true,
    );
    final property = RegExp(
      '^\\s*${RegExp.escape(field)}\\s+(?:"([^"\\r\\n]+)"|([^\\s)]+))',
      multiLine: true,
    );
    final entries = <String, String>{};
    final ambiguous = <String>{};
    for (final game in games.allMatches(document)) {
      final body = game[1]!;
      final label = name.firstMatch(body)?[1]?.trim().toLowerCase();
      final match = property.firstMatch(body);
      final value = (match?[1] ?? match?[2])?.trim();
      if (label == null || value == null || value.isEmpty) continue;
      final existing = entries.putIfAbsent(label, () => value);
      if (existing != value) ambiguous.add(label);
    }
    entries.removeWhere((label, _) => ambiguous.contains(label));
    return entries;
  }
}
