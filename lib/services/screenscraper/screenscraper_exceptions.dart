/// Exceptions thrown by the ScreenScraper service layer.
class ScreenscraperQuotaExceededException implements Exception {
  final String message;

  ScreenscraperQuotaExceededException([this.message = '']);

  @override
  String toString() =>
      'ScreenscraperQuotaExceededException: ${message.isEmpty ? 'Daily scraping quota exceeded' : message}';
}

class ScreenscraperDeveloperCredentialsException implements Exception {
  const ScreenscraperDeveloperCredentialsException();

  @override
  String toString() =>
      'ScreenScraper developer credentials are missing or incomplete';
}

class ScreenscraperRequestException implements Exception {
  final String endpoint;
  final int status;

  const ScreenscraperRequestException(this.endpoint, this.status);

  @override
  String toString() => 'ScreenScraper $endpoint: HTTP $status';
}

class ScreenscraperCancelledException implements Exception {
  const ScreenscraperCancelledException();
}
