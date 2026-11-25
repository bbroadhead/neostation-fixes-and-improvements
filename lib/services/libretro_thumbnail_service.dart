import '../utils/artwork_title.dart';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;

import '../models/artwork_preview.dart';
import '../models/artwork_scrape_event.dart';
import '../models/game_model.dart';
import '../models/system_family.dart';
import 'artwork_assignment_service.dart';
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
      _playlists[parentSystemId(appSystemId)];

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
    if (searchTitle != null) {
      final query = searchTitle.trim().toLowerCase();
      // The thumbnail filenames can include region and revision suffixes.
      labels.addAll(
        _labels(
          stem,
          gameName,
          null,
        ).where((label) => label.toLowerCase().contains(query)),
      );
    }
    Future<List<ArtworkPreview>> fetch(Set<String> names) async {
      final candidates = await Future.wait([
        for (final type in _folders.entries)
          for (final label in names)
            _preview(base, playlist, type, label, shouldCancel),
      ]);
      return candidates.nonNulls.toList();
    }

    final previews = await fetch(labels);
    if (previews.isNotEmpty ||
        searchTitle == null ||
        (shouldCancel?.call() ?? false)) {
      return previews;
    }
    final indexed = await _catalogueLabels(
      base,
      playlist,
      searchTitle,
      shouldCancel,
    );
    return fetch(indexed.difference(labels));
  }

  static Future<Set<String>> _catalogueLabels(
    Uri base,
    String playlist,
    String query,
    bool Function()? shouldCancel,
  ) async {
    final wanted = ArtworkTitle.normalized(query);
    if (wanted.isEmpty) return {};
    try {
      final response = await ScreenscraperClient.httpGetWithRetry(
        base.replace(
          pathSegments: [
            ...base.pathSegments.where((segment) => segment.isNotEmpty),
            playlist,
            'Named_Titles',
            '',
          ],
        ),
        timeout: const Duration(seconds: 12),
        maxRetries: 1,
        shouldCancel: shouldCancel,
      );
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 2 * 1024 * 1024) {
        return {};
      }
      final exact = <String>{};
      final partial = <String>{};
      for (final match in RegExp(
        r'href="([^"<>/]+\.png)"',
        caseSensitive: false,
      ).allMatches(response.body)) {
        if (shouldCancel?.call() ?? false) return {};
        String filename;
        try {
          filename = Uri.decodeComponent(match[1]!);
        } on FormatException {
          continue;
        } on ArgumentError {
          continue;
        }
        final label = filename.substring(0, filename.length - 4);
        final comparable = ArtworkTitle.normalized(label);
        if (comparable == wanted) {
          exact.add(label);
          if (exact.length == 4) return exact;
        } else if (partial.length < 4 &&
            wanted.length >= 4 &&
            ' $comparable '.contains(' $wanted ')) {
          partial.add(label);
        }
      }
      return exact.isEmpty ? partial : exact;
    } catch (error) {
      if (!(shouldCancel?.call() ?? false)) {
        _log.w('Libretro title index unavailable (${error.runtimeType})');
      }
      return {};
    }
  }

  static Future<ArtworkPreview?> _preview(
    Uri base,
    String playlist,
    MapEntry<String, String> type,
    String title,
    bool Function()? shouldCancel, {
    void Function()? onFailure,
  }) async {
    try {
      final response = await ScreenscraperClient.httpGetWithRetry(
        _artworkUrl(base, playlist, type.value, title),
        timeout: const Duration(seconds: 15),
        shouldCancel: shouldCancel,
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        onFailure?.call();
        _log.w(
          'Libretro ${type.value} HTTP ${response.statusCode} for "$title"',
        );
        return null;
      }
      if (!await _isDecodablePng(response.bodyBytes)) {
        onFailure?.call();
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
      if (!(shouldCancel?.call() ?? false)) onFailure?.call();
      _log.w('Libretro preview ${type.value}: ${error.runtimeType}');
      return null;
    }
  }

  static Set<String> _labels(String stem, String? title, String? searchTitle) {
    final labels = {
      if (searchTitle != null)
        searchTitle
      else ...[
        stem,
        if (title != null) title.trim(),
      ],
    }..remove('');
    for (final label in labels.toList()) {
      final modern = label
          .replaceFirst(
            RegExp(
              r'(?<=\([UEJ]\))\s*(?:\[(?:!|c|[abfhopt][0-9]+)\]\s*)+$',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll('(U)', '(USA)')
          .replaceAll('(E)', '(Europe)')
          .replaceAll('(J)', '(Japan)');
      if (modern != label) labels.add(modern);
    }
    return labels;
  }

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
    ArtworkScrapeObserver? onArtwork,
    bool Function(String category)? providerFailed,
    Uri? catalog,
    bool Function()? shouldCancel,
    Stream<ArtworkPreview> Function(String category)? preferred,
    Stream<ArtworkPreview> Function(
      String category,
      Future<ArtworkPreview?> Function() readLibretro,
    )?
    prioritized,
    Future<ArtworkPreview?> Function(String category)? fallback,
  }) async {
    final playlist = _playlists[parentSystemId(appSystemId)];
    if (playlist == null && preferred == null && prioritized == null) {
      return false;
    }

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
    final types = {..._folders.keys, ...enabledMediaTypes}
        .where(
          (type) =>
              enabledMediaTypes.contains(type) &&
              (_folders.containsKey(type) ||
                  ((preferred != null || prioritized != null) &&
                      const {'fanart', 'wheel', 'icons'}.contains(type))),
        )
        .toList();

    var available = false;
    for (final (index, type) in types.indexed) {
      if (shouldCancel?.call() ?? false) break;
      final folder = ScreenscraperMediaResolver.mapMediaTypeToFolder(type);
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
      if (hasManual) onArtwork?.call(folder, ArtworkScrapeEvent.skippedManual);
      if (!hasManual && (!cached || forceOverwrite)) {
        ArtworkPreview? selected;
        var failed = false;
        Future<ArtworkPreview?> readLibretro() async {
          final libretroFolder = _folders[type];
          if (playlist == null || libretroFolder == null) return null;
          for (final label in labels) {
            final result = await _preview(
              base,
              playlist,
              MapEntry(type, libretroFolder),
              label,
              shouldCancel,
              onFailure: () => failed = true,
            );
            if (result != null || (shouldCancel?.call() ?? false)) {
              return result;
            }
          }
          return null;
        }

        final candidates =
            prioritized?.call(folder, readLibretro) ??
            preferred?.call(folder) ??
            const Stream<ArtworkPreview>.empty();
        await for (final image in candidates) {
          if (shouldCancel?.call() ?? false) return available;
          if (image.category != folder) continue;
          if (await ArtworkAssignmentService.isReadable(image)) {
            selected = image;
            break;
          }
          failed = true;
        }
        if (selected == null && prioritized == null) {
          selected = await readLibretro();
        }
        if (shouldCancel?.call() ?? false) return available;
        if (selected == null && fallback != null) {
          final image = await fallback(folder);
          if (image != null) {
            if (image.category == folder &&
                await ArtworkAssignmentService.isReadable(image)) {
              selected = image;
            } else {
              failed = true;
            }
          }
        }
        if (shouldCancel?.call() ?? false) return available;
        if (selected == null && !cached) {
          onArtwork?.call(
            folder,
            failed || (providerFailed?.call(folder) ?? false)
                ? ArtworkScrapeEvent.failed
                : ArtworkScrapeEvent.unavailable,
          );
        }
        if (selected != null) {
          onArtwork?.call(folder, ArtworkScrapeEvent.downloaded);
          if ((await manual?.exists() ?? false) ||
              (!forceOverwrite && await _hasLocalArtwork(file))) {
            available = true;
          } else {
            try {
              await ArtworkAssignmentService.save(
                file,
                selected,
                manual: false,
              );
              final saved = await ArtworkAssignmentService.readProvenance(
                file,
                folder,
              );
              if (saved?.source != selected.provider ||
                  saved?.manual != false) {
                throw FileSystemException(
                  'Could not verify saved artwork',
                  file.path,
                );
              }
              available = true;
              onArtwork?.call(folder, ArtworkScrapeEvent.assigned);
            } on FileSystemException catch (error) {
              onArtwork?.call(folder, ArtworkScrapeEvent.failed);
              _log.w('Artwork $folder for "$romName": ${error.runtimeType}');
            }
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
      final file = File('$stem.$extension');
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) continue;
      try {
        if (await ArtworkAssignmentService.isImageReadable(
          await file.readAsBytes(),
        )) {
          return true;
        }
      } on FileSystemException {
        // An unreadable cache file is eligible for repair.
      }
    }
    return false;
  }
}
