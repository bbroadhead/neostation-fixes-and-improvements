import 'dart:io';

import 'package:path/path.dart' as path;

import '../utils/atomic_file_writer.dart';
import 'logger_service.dart';
import 'screenscraper/media_resolver.dart';
import 'screenscraper/rom_hasher.dart';
import 'screenscraper/screenscraper_client.dart';

/// RetroArch's public artwork catalog, indexed by playlist and game label.
class LibretroThumbnailService {
  static final _log = LoggerService.instance;

  static const _playlists = {
    '2600': 'Atari - 2600',
    '5200': 'Atari - 5200',
    '7800': 'Atari - 7800',
    'lynx': 'Atari - Lynx',
    'jag': 'Atari - Jaguar',
    'c64': 'Commodore - 64',
    '3do': 'The 3DO Company - 3DO',
    'nes': 'Nintendo - Nintendo Entertainment System',
    'fc': 'Nintendo - Nintendo Entertainment System',
    'fds': 'Nintendo - Family Computer Disk System',
    'snes': 'Nintendo - Super Nintendo Entertainment System',
    'sfc': 'Nintendo - Super Nintendo Entertainment System',
    'gb': 'Nintendo - Game Boy',
    'gbc': 'Nintendo - Game Boy Color',
    'gba': 'Nintendo - Game Boy Advance',
    'n64': 'Nintendo - Nintendo 64',
    'nds': 'Nintendo - Nintendo DS',
    'ds': 'Nintendo - Nintendo DS',
    '3ds': 'Nintendo - Nintendo 3DS',
    'gc': 'Nintendo - GameCube',
    'wii': 'Nintendo - Wii',
    'vb': 'Nintendo - Virtual Boy',
    'sms': 'Sega - Master System - Mark III',
    'gg': 'Sega - Game Gear',
    'md': 'Sega - Mega Drive - Genesis',
    'genesis': 'Sega - Mega Drive - Genesis',
    '32x': 'Sega - 32X',
    'mcd': 'Sega - Mega-CD - Sega CD',
    'scd': 'Sega - Mega-CD - Sega CD',
    'sat': 'Sega - Saturn',
    'dc': 'Sega - Dreamcast',
    'sg1k': 'Sega - SG-1000',
    'ps1': 'Sony - PlayStation',
    'ps2': 'Sony - PlayStation 2',
    'psp': 'Sony - PlayStation Portable',
    'pce': 'NEC - PC Engine - TurboGrafx 16',
    'tg16': 'NEC - PC Engine - TurboGrafx 16',
    'pccd': 'NEC - PC Engine CD - TurboGrafx-CD',
    'tgcd': 'NEC - PC Engine CD - TurboGrafx-CD',
    'ngp': 'SNK - Neo Geo Pocket',
    'ngpc': 'SNK - Neo Geo Pocket Color',
    'ws': 'Bandai - WonderSwan',
    'wsc': 'Bandai - WonderSwan Color',
  };

  static bool supportsSystem(String appSystemId) =>
      _playlists.containsKey(appSystemId);

  static const _folders = {'box2D': 'Named_Boxarts', 'ss': 'Named_Snaps'};

  static final _invalidLabelCharacters = RegExp(r'''[&*/:`"<>?\\|]''');
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  /// Returns whether any requested image is available locally after the run.
  /// A catalog miss leaves existing art available and can be retried later.
  static Future<bool> download({
    required String appSystemId,
    required String systemFolder,
    required String romName,
    required List<String> enabledMediaTypes,
    String? gameName,
    bool forceOverwrite = false,
    void Function(double)? onProgress,
    Uri? catalog,
  }) async {
    final playlist = _playlists[appSystemId];
    if (playlist == null) return false;

    final stem = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );
    if (stem.isEmpty ||
        path.basename(stem) != stem ||
        path.basename(systemFolder) != systemFolder ||
        systemFolder.isEmpty ||
        systemFolder == '.' ||
        systemFolder == '..') {
      return false;
    }
    final labels = {
      stem,
      if (gameName != null && gameName.trim().isNotEmpty) gameName.trim(),
    };
    final root = await ScreenscraperMediaResolver.getMediaDirectory();
    final base = catalog ?? Uri.https('thumbnails.libretro.com', '/');
    final types = _folders.entries
        .where((e) => enabledMediaTypes.contains(e.key))
        .toList();

    var available = false;
    for (final (index, type) in types.indexed) {
      final folder = ScreenscraperMediaResolver.mapMediaTypeToFolder(type.key);
      final file = File(path.join(root, systemFolder, folder, '$stem.png'));
      final cached = await file.exists() && await file.length() > 0;
      available = available || cached;
      if (!cached || forceOverwrite) {
        for (final label in labels) {
          final safeLabel = label.replaceAll(_invalidLabelCharacters, '_');
          final url = base.replace(
            pathSegments: [playlist, type.value, '$safeLabel.png'],
          );
          try {
            final response = await ScreenscraperClient.httpGetWithRetry(
              url,
              timeout: const Duration(seconds: 15),
            );
            if (response.statusCode == 404) continue;
            if (response.statusCode != 200 ||
                response.bodyBytes.length <= _pngSignature.length ||
                !Iterable<int>.generate(_pngSignature.length)
                    .every((i) => response.bodyBytes[i] == _pngSignature[i])) {
              _log.w(
                'Libretro ${type.value} HTTP ${response.statusCode} for "$romName"',
              );
              break;
            }
            await writeFileAtomically(file, response.bodyBytes);
            available = true;
            break;
          } catch (error) {
            _log.w(
              'Libretro ${type.value} for "$romName": ${error.runtimeType}',
            );
            break;
          }
        }
      }
      onProgress?.call((index + 1) / types.length);
    }
    return available;
  }
}
