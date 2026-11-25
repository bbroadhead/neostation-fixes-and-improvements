import 'package:http/http.dart' as http;

/// Finds community guides by the game ID in RetroAchievements' wiki directory.
class RaGuideService {
  static final _wiki = Uri.parse(
    'https://github.com/RetroAchievements/guides/wiki/',
  );
  static const _systems = {
    'nes': 'NES',
    'snes': 'SNES',
    'n64': 'Nintendo-64',
    'gc': 'GameCube',
    'wii': 'Wii',
    'gb': 'Game-Boy',
    'gbc': 'Game-Boy-Color',
    'gba': 'Game-Boy-Advance',
    'ds': 'Nintendo-DS',
    'ps1': 'PlayStation',
    'ps2': 'PlayStation-2',
    'psp': 'PlayStation-Portable',
    'genesis': 'Genesis',
    'dc': 'Dreamcast',
    'gg': 'Game-Gear',
  };

  static Future<Uri> resolve(
    int gameId,
    String system, {
    http.Client? client,
  }) async {
    final fallback = Uri.https('retroachievements.org', '/game/$gameId');
    final page = _systems[system.replaceFirst(RegExp(r'-hacks$'), '')];
    if (page == null) return fallback;
    final uri = _wiki.resolve(page);
    try {
      final result = await (client == null ? http.get(uri) : client.get(uri))
          .timeout(const Duration(seconds: 4));
      if (result.statusCode != 200) return fallback;
      final links = RegExp(
        r'''href\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      final rows = RegExp(
        r'<tr\b[^>]*>(.*?)</tr>',
        dotAll: true,
        caseSensitive: false,
      );
      for (final row in rows.allMatches(result.body)) {
        final urls = links
            .allMatches(row[1]!)
            .map((match) => uri.resolve(match[1]!))
            .toList();
        if (!urls.any(
          (link) => link.host == fallback.host && link.path == fallback.path,
        ))
          continue;
        for (final link in urls) {
          if (link.scheme == 'https' &&
              link.host == _wiki.host &&
              link.path.startsWith(_wiki.path) &&
              link.path != uri.path &&
              link.userInfo.isEmpty) {
            return link;
          }
        }
      }
    } on Exception {
      return fallback;
    }
    return fallback;
  }
}
