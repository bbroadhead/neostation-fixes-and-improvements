import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:neostation/services/logger_service.dart';

import 'screenscraper_exceptions.dart';
import '../../utils/semaphore.dart';

/// HTTP transport, rate limiting, and request identity for ScreenScraper.
///
/// Owns the shared HTTP client (certificate-verifying), the request
/// semaphore and the rolling daily-request counter, and builds the softname that
/// identifies NeoStation to the API. [httpGetWithRetry] performs every GET with
/// exponential backoff, concurrency limiting and daily-quota enforcement; the
/// rate-limit configuration ([updateRequestSemaphore]/[initializeDailyCounter])
/// is set by the scrape orchestration. Extracted verbatim from
/// [ScreenScraperService]; behaviour is unchanged. Sole owner of the request
/// semaphore + daily counter (single-owner static state).
class ScreenscraperClient {
  ScreenscraperClient._();

  static final _log = LoggerService.instance;

  static String? _appVersion;

  /// Retrieves the application version and platform to identify requests to the API.
  static Future<String> getSoftname() async {
    if (_appVersion != null) return _appVersion!;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final name = packageInfo.appName.isNotEmpty
          ? packageInfo.appName
          : 'neostation';
      final version = packageInfo.version;

      String platform = '';
      if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      } else if (Platform.isWindows) {
        platform = 'windows';
      } else if (Platform.isLinux) {
        platform = 'linux';
      } else if (Platform.isMacOS) {
        platform = 'macos';
      }
      _appVersion = '$name-$version-$platform';
      return _appVersion!;
    } catch (e) {
      _appVersion = 'neostation';
      return _appVersion!;
    }
  }

  /// Persistent HTTP client shared by every ScreenScraper request.
  static final http.Client _httpClient = createHttpClient();

  /// Builds the HTTP client used for ScreenScraper requests.
  ///
  /// Certificates are verified against the platform's trusted roots. Every
  /// request carries the developer and user credentials in its query string,
  /// so a client that accepted any certificate would hand them to anyone able
  /// to intercept the connection. [context] replaces the trusted roots in
  /// tests.
  @visibleForTesting
  static http.Client createHttpClient({SecurityContext? context}) =>
      IOClient(HttpClient(context: context));

  static Semaphore _requestSemaphore = Semaphore(1);

  static int _dailyRequestsCount = 0;
  static DateTime? _lastRequestDate;

  /// Updates the request semaphore concurrency limit.
  static void updateRequestSemaphore(int maxThreads) {
    if (_requestSemaphore.maxCount != maxThreads) {
      _requestSemaphore = Semaphore(maxThreads);
    }
  }

  /// Resets or initializes the daily request counter based on the current date.
  static void initializeDailyCounter(int currentRequests) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_lastRequestDate == null ||
        !_lastRequestDate!.isAtSameMomentAs(today)) {
      _dailyRequestsCount = currentRequests;
      _lastRequestDate = today;
    }
  }

  static final _random = Random();
  static final _retryAfter = <String, DateTime>{};
  static const _retryableStatuses = {429, 500, 502, 503, 504};

  /// Performs a bounded number of GET attempts through the shared request queue.
  static Future<http.Response> httpGetWithRetry(
    Uri url, {
    Map<String, String>? headers,
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 40),
    int? maxDailyRequests,
    bool Function()? shouldCancel,
  }) async {
    final endpoint = url.pathSegments.firstOrNull == 'api2'
        ? url.pathSegments.last
        : 'media/request';
    final origin = url.origin;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      final semaphore = _requestSemaphore;
      await semaphore.acquire();
      try {
        if (shouldCancel?.call() ?? false) {
          throw const ScreenscraperCancelledException();
        }
        final holdUntil = _retryAfter[origin];
        if (holdUntil != null && holdUntil.isAfter(DateTime.now())) {
          // Return a rate-limit response when the requested pause would exceed
          // the caller's timeout. Further calls still honor the cooldown.
          final wait = holdUntil.difference(DateTime.now());
          if (wait > timeout) return http.Response('', 429);
          await Future<void>.delayed(wait);
        }
        initializeDailyCounter(0);
        if (maxDailyRequests != null &&
            maxDailyRequests > 0 &&
            _dailyRequestsCount >= maxDailyRequests) {
          throw ScreenscraperQuotaExceededException();
        }
        _dailyRequestsCount++;
        if (shouldCancel?.call() ?? false) {
          throw const ScreenscraperCancelledException();
        }
        final response = await _get(url, headers, timeout, shouldCancel);
        if (response.statusCode == 430 || response.statusCode == 431) {
          throw ScreenscraperQuotaExceededException(
            'Daily scraping quota exceeded (HTTP ${response.statusCode})',
          );
        }
        if (!_retryableStatuses.contains(response.statusCode)) return response;
        final pause = _parseRetryAfter(response.headers['retry-after']);
        if (pause != null || response.statusCode == 429) {
          final until = DateTime.now().add(pause ?? _backoff(attempt));
          final existing = _retryAfter[origin];
          if (existing == null || until.isAfter(existing)) {
            _retryAfter[origin] = until;
          }
          if (pause != null && pause > timeout) return response;
        }
        if (attempt == maxRetries) return response;
        _log.w(
          'ScreenScraper $endpoint HTTP ${response.statusCode}, retrying after attempt $attempt',
        );
      } on TimeoutException {
        _log.w('ScreenScraper $endpoint timed out on attempt $attempt');
        if (attempt == maxRetries) rethrow;
      } on http.ClientException catch (error) {
        if (shouldCancel?.call() ?? false) {
          throw const ScreenscraperCancelledException();
        }
        _log.w(
          'ScreenScraper $endpoint ${error.runtimeType} on attempt $attempt',
        );
        if (attempt == maxRetries) {
          // ClientException can include the credential-bearing request URI.
          throw const SocketException('ScreenScraper connection failed');
        }
      } finally {
        semaphore.release();
      }
      await Future<void>.delayed(_backoff(attempt));
    }
    throw ArgumentError.value(maxRetries, 'maxRetries', 'Must be positive');
  }

  static Duration _backoff(int attempt) => Duration(
    milliseconds: 500 * (1 << min(attempt - 1, 4)) + _random.nextInt(251),
  );

  static Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null) {
      return Duration(seconds: max(0, min(seconds, 86400)));
    }
    try {
      final delay = HttpDate.parse(header).difference(DateTime.now());
      return delay.isNegative ? Duration.zero : delay;
    } on FormatException {
      return null;
    }
  }

  static Future<http.Response> _get(
    Uri url,
    Map<String, String>? headers,
    Duration timeout,
    bool Function()? shouldCancel,
  ) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    )..followRedirects = false;
    if (headers != null) request.headers.addAll(headers);
    final cancellationTimer = shouldCancel == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (shouldCancel() && !abort.isCompleted) abort.complete();
          });
    try {
      return await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException(
                'ScreenScraper request timed out',
                timeout,
              );
            },
          );
    } finally {
      cancellationTimer?.cancel();
    }
  }
}
