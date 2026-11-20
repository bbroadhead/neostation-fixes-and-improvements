import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;

import '../models/artwork_preview.dart';
import '../models/game_model.dart';
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
    'ard': 'Arduboy Inc - Arduboy',
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

  static String? playlistForSystem(String appSystemId) =>
      _playlists[appSystemId];

  static bool supportsSystem(String appSystemId) =>
      playlistForSystem(appSystemId) != null;

  static const titleScreens = 'title_screens';
  static const _folders = {
    'box2D': 'Named_Boxarts',
    'ss': 'Named_Snaps',
    titleScreens: 'Named_Titles',
  };

  static final _invalidLabelCharacters = RegExp(r'''[&*/:`"<>?\\|]''');
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  static Future<List<ArtworkPreview>> gallery({
    required String appSystemId,
    required String romName,
    required String gameName,
    String? searchTitle,
    Uri? catalog,
    bool Function()? shouldCancel,
  }) async {
    final playlist = playlistForSystem(appSystemId);
    if (playlist == null) return [];
    final stem = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );
    final base = catalog ?? Uri.https('thumbnails.libretro.com', '/');
    final labels = _labels(stem, gameName, searchTitle);
    final candidates = await Future.wait([
      for (final type in _folders.entries)
        for (final label in labels)
          _preview(base, playlist, type, label, shouldCancel),
    ]);
    return candidates.nonNulls.toList();
  }

  static Future<ArtworkPreview?> _preview(
    Uri base,
    String playlist,
    MapEntry<String, String> type,
    String title,
    bool Function()? shouldCancel,
  ) async {
    try {
      final response = await ScreenscraperClient.httpGetWithRetry(
        _artworkUrl(base, playlist, type.value, title),
        timeout: const Duration(seconds: 15),
        shouldCancel: shouldCancel,
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        _log.w(
          'Libretro ${type.value} HTTP ${response.statusCode} for "$title"',
        );
        return null;
      }
      if (!await _isDecodablePng(response.bodyBytes)) {
        _log.w('Libretro ${type.value} invalid PNG for "$title"');
        return null;
      }
      return (
        provider: ArtworkProvider.libretro,
        category: ScreenscraperMediaResolver.mapMediaTypeToFolder(type.key),
        title: title,
        bytes: response.bodyBytes,
      );
    } catch (error) {
      _log.w('Libretro preview ${type.value}: ${error.runtimeType}');
      return null;
    }
  }

  static Set<String> _labels(String stem, String? title, String? searchTitle) =>
      {
        if (searchTitle != null)
          searchTitle
        else ...[
          stem,
          if (title != null && title.trim().isNotEmpty) title.trim(),
        ],
      }..remove('');

  static Uri _artworkUrl(
    Uri base,
    String playlist,
    String folder,
    String label,
  ) {
    final safeLabel = label.replaceAll(_invalidLabelCharacters, '_');
    return base.replace(pathSegments: [playlist, folder, '$safeLabel.png']);
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length > _pngSignature.length &&
      Iterable<int>.generate(_pngSignature.length)
          .every((i) => bytes[i] == _pngSignature[i]);

  static Future<bool> _isDecodablePng(Uint8List bytes) async {
    if (!_isPng(bytes)) return false;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        return true;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  /// Returns whether any requested image is available locally after the run.
  /// A catalog miss leaves existing art available and can be retried later.
  static Future<bool> download({
    required String appSystemId,
    required String systemFolder,
    required String romName,
    required List<String> enabledMediaTypes,
    String? romPath,
    String? gameName,
    String? searchTitle,
    bool forceOverwrite = false,
    void Function(double)? onProgress,
    Uri? catalog,
    bool Function()? shouldCancel,
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
    final labels = _labels(stem, gameName, searchTitle);
    final root = await ScreenscraperMediaResolver.getMediaDirectory();
    final base = catalog ?? Uri.https('thumbnails.libretro.com', '/');
    final types = _folders.entries
        .where((e) => enabledMediaTypes.contains(e.key))
        .toList();

    var available = false;
    for (final (index, type) in types.indexed) {
      if (shouldCancel?.call() ?? false) break;
      final folder = ScreenscraperMediaResolver.mapMediaTypeToFolder(type.key);
      final file = File(path.join(root, systemFolder, folder, '$stem.png'));
      final manual = romPath == null
          ? null
          : File(
              GameModel.artworkOverridePathForRom(
                romPath,
                folder,
                mediaDirectory: root,
              ),
            );
      final hasManual = await manual?.exists() ?? false;
      final cached = hasManual || await _hasLocalArtwork(file);
      available = available || cached;
      if (!hasManual && (!cached || forceOverwrite)) {
        for (final label in labels) {
          final preview = await _preview(
            base,
            playlist,
            type,
            label,
            shouldCancel,
          );
          if (shouldCancel?.call() ?? false) return available;
          if (preview == null) continue;
          if ((await manual?.exists() ?? false) ||
              (!forceOverwrite && await _hasLocalArtwork(file))) {
            available = true;
            break;
          }
          try {
            await writeFileAtomically(file, preview.bytes);
            available = true;
            break;
          } on FileSystemException catch (error) {
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

  static Future<bool> _hasLocalArtwork(File png) async {
    final stem = path.withoutExtension(png.path);
    for (final extension in const ['png', 'jpg', 'webp']) {
      final stat = await File('$stem.$extension').stat();
      if (stat.type == FileSystemEntityType.file && stat.size > 0) return true;
    }
    return false;
  }
}
