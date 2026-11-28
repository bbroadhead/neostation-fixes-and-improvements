import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/utils/atomic_file_writer.dart';

import '../../models/artwork_scrape_event.dart';
import '../../models/game_model.dart';
import '../artwork_assignment_service.dart';
import 'region_config.dart';
import 'rom_hasher.dart';
import 'media_resolver.dart';
import 'screenscraper_client.dart';
import 'screenscraper_exceptions.dart';

/// Media asset downloader for ScreenScraper.
///
/// Downloads a game's media assets (boxart, screenshots, etc.) in bounded
/// concurrent batches, selecting the best regional/language variant, mapping
/// media types to folders, and skipping assets already on disk. Delegates
/// transport to [ScreenscraperClient], resolution to [ScreenscraperMediaResolver]
/// / [ScreenscraperRegionConfig], and ROM naming to [ScreenscraperRomHasher].
/// Extracted from [ScreenScraperService].
/// Stateless — holds only the shared logger.
class ScreenscraperMediaDownloader {
  ScreenscraperMediaDownloader._();

  static final _log = LoggerService.instance;

  static final RegExp _safeExtension = RegExp(r'^[A-Za-z0-9]{1,8}$');

  /// Downloads and caches a media file.
  static Future<bool> _downloadMediaFileSmart(
    String url,
    String relativePath,
    String userDataDir, {
    bool forceOverwrite = false,
    int? maxDailyRequests,
    bool Function()? shouldCancel,
    void Function(ArtworkScrapeEvent)? onArtwork,
  }) async {
    try {
      final fullPath = path.join(userDataDir, relativePath);
      final file = File(fullPath);
      if (await file.exists() && !forceOverwrite) {
        return true;
      }

      final response = await ScreenscraperClient.httpGetWithRetry(
        Uri.parse(url),
        timeout: const Duration(seconds: 60),
        maxRetries: 2,
        maxDailyRequests: maxDailyRequests,
        shouldCancel: shouldCancel,
      );
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (response.statusCode == 200 &&
          response.bodyBytes.isNotEmpty &&
          !contentType.startsWith('text/html') &&
          !contentType.contains('json')) {
        // A file left half-written would count as downloaded from then on.
        if (shouldCancel?.call() ?? false) return false;
        onArtwork?.call(ArtworkScrapeEvent.downloaded);
        await writeFileAtomically(file, response.bodyBytes);
        onArtwork?.call(ArtworkScrapeEvent.assigned);
        if (forceOverwrite) {
          final stem = path.withoutExtension(fullPath);
          for (final extension in ['png', 'jpg', 'jpeg', 'webp', 'mp4']) {
            final previous = File('$stem.$extension');
            if (previous.path != fullPath && await previous.exists()) {
              await previous.delete();
            }
          }
        }
        return true;
      } else {
        onArtwork?.call(
          response.statusCode == 404
              ? ArtworkScrapeEvent.unavailable
              : ArtworkScrapeEvent.failed,
        );
        _log.e(
          'ScreenScraper artwork HTTP ${response.statusCode}: $relativePath',
        );
        return false;
      }
    } on ScreenscraperCancelledException {
      return false;
    } on ScreenscraperQuotaExceededException {
      // Every later request would be refused too; the caller says why.
      rethrow;
    } catch (e) {
      if (!(shouldCancel?.call() ?? false)) {
        onArtwork?.call(ArtworkScrapeEvent.failed);
      }
      _log.e('ScreenScraper artwork $relativePath: ${e.runtimeType}');
      return false;
    }
  }

  /// Downloads multiple media assets for a game, managing concurrency.
  ///
  /// Throws [ScreenscraperQuotaExceededException] when ScreenScraper refuses a
  /// download because the day's quota is used up: the batch under way
  /// finishes, and no later batch is requested.
  static Future<Map<String, dynamic>> downloadGameMedia(
    String systemFolder,
    String romName,
    List<dynamic> medias,
    int maxThreads, {
    String? appSystemId,
    String? preferredLanguage,
    bool Function()? shouldCancel,
    Function(double progress)? onProgress,
    List<String>? allowedMediaTypes,
    bool forceOverwrite = false,
    int? maxDailyRequests,
    String? romPath,
    ArtworkScrapeObserver? onArtwork,
  }) async {
    if (medias.isEmpty && onArtwork == null && romPath == null) {
      return {'success': true, 'cancelled': false};
    }
    final userDataDir = await ScreenscraperMediaResolver.getMediaDirectory();
    final regionPriority = await ScreenscraperRegionConfig.getRegionPriority();
    final mediaTypes =
        allowedMediaTypes ?? ['fanart', 'ss', 'video', 'wheel', 'box2D'];

    final romBaseName = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );
    final downloadTasks =
        <({String url, String relativePath, String category, bool image})>[];
    for (final mediaType in mediaTypes.toSet()) {
      if (shouldCancel?.call() ?? false) {
        return {'success': false, 'cancelled': true};
      }
      final folder = ScreenscraperMediaResolver.mapMediaTypeToFolder(mediaType);
      final image = mediaType != 'video';
      if (image &&
          romPath != null &&
          await ArtworkAssignmentService.hasManualDecision(
            File(
              GameModel.artworkOverridePathForRom(
                romPath,
                folder,
                mediaDirectory: userDataDir,
              ),
            ),
          )) {
        onArtwork?.call(folder, ArtworkScrapeEvent.skippedManual);
        continue;
      }
      final bestMedia = ScreenscraperMediaResolver.selectBestMedia(
        medias,
        mediaType,
        preferredLanguage: preferredLanguage,
        regionPriority: regionPriority,
      );
      if (bestMedia == null) {
        final stem = path.join(userDataDir, systemFolder, folder, romBaseName);
        var cached = false;
        for (final extension in const [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'mp4',
          'webm',
        ]) {
          if (await File('$stem.$extension').exists()) {
            cached = true;
            break;
          }
        }
        if (!cached) onArtwork?.call(folder, ArtworkScrapeEvent.unavailable);
        continue;
      }
      final format = bestMedia['format']?.toString() ?? 'png';
      if (!_safeExtension.hasMatch(format)) {
        _log.w('Skipping $mediaType for $romName: unexpected format');
        onArtwork?.call(folder, ArtworkScrapeEvent.failed);
        continue;
      }
      downloadTasks.add((
        url: bestMedia['url'].toString(),
        relativePath: '$systemFolder/$folder/$romBaseName.$format',
        category: folder,
        image: image,
      ));
    }

    if (downloadTasks.isEmpty) {
      return {'success': true, 'cancelled': false};
    }

    final batches =
        <
          List<({String url, String relativePath, String category, bool image})>
        >[];
    for (var i = 0; i < downloadTasks.length; i += maxThreads) {
      final end = (i + maxThreads < downloadTasks.length)
          ? i + maxThreads
          : downloadTasks.length;
      batches.add(downloadTasks.sublist(i, end));
    }

    int succeeded = 0;
    bool wasCancelled = false;

    int completedTasks = 0;
    for (final batch in batches) {
      if (shouldCancel != null && shouldCancel()) {
        wasCancelled = true;
        break;
      }

      final results = await Future.wait(
        batch.map(
          (task) => _downloadMediaFileSmart(
            task.url,
            task.relativePath,
            userDataDir,
            forceOverwrite: forceOverwrite,
            maxDailyRequests: maxDailyRequests,
            shouldCancel: shouldCancel,
            onArtwork: (event) {
              if (task.image ||
                  event == ArtworkScrapeEvent.failed ||
                  event == ArtworkScrapeEvent.unavailable) {
                onArtwork?.call(task.category, event);
              }
            },
          ),
        ),
      );
      succeeded += results.where((ok) => ok).length;

      completedTasks += batch.length;
      if (onProgress != null) onProgress(completedTasks / downloadTasks.length);

      if (batches.length > 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    wasCancelled = wasCancelled || (shouldCancel?.call() ?? false);
    return {
      'success': succeeded == downloadTasks.length && !wasCancelled,
      'cancelled': wasCancelled,
    };
  }
}
