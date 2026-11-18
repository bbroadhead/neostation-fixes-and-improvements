import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/screenscraper_service.dart';

/// Signing in to ScreenScraper with the day's quota used up said "Could not
/// reach ScreenScraper. Check your internet connection" instead of the quota
/// message: the HTTP client throws on a 430, and the sign-in check took that
/// for a network failure.
void main() {
  late HttpServer server;
  late int status;
  late String body;
  late int requests;

  setUp(() async {
    body = 'refused';
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests++;
      request.response
        ..statusCode = status
        ..write(body)
        ..close();
    });
    ScreenScraperService.baseUrl = 'http://127.0.0.1:${server.port}/api2';
  });

  tearDown(() async {
    ScreenScraperService.baseUrl = ScreenScraperService.defaultBaseUrl;
    await server.close(force: true);
  });

  test('a sign-in refused for the day\'s quota says so', () async {
    status = 430;

    final result = await ScreenScraperService.verifyCredentials('user', 'pw');

    expect(result.failure, ScreenScraperAuthFailure.quotaExceeded);
  });

  test('a wrong password is still reported as one', () async {
    status = 403;
    body = 'Vérifier vos identifiants utilisateur';

    final result = await ScreenScraperService.verifyCredentials('user', 'pw');

    expect(result.failure, ScreenScraperAuthFailure.invalidCredentials);
  });

  test('developer rejection is distinct and is not retried', () async {
    status = 403;
    body = 'Vérifier vos identifiants développeur';
    final result = await ScreenScraperService.verifyCredentials('user', 'pw');
    expect(result.failure, ScreenScraperAuthFailure.developerCredentials);
    expect(requests, 1);
  });

  test('generic forbidden response does not attribute blame', () async {
    status = 403;
    final result = await ScreenScraperService.verifyCredentials('user', 'pw');
    expect(result.failure, ScreenScraperAuthFailure.authorizationDenied);
    expect(requests, 1);
  });

  test('accepts a successful response for the submitted account', () async {
    status = 200;
    body = '{"header":{"success":true},"response":{"ssuser":{"id":"User"}}}';
    final result = await ScreenScraperService.verifyCredentials('user', 'pw');
    expect(result.isSuccess, isTrue);
  });

  test('rejects malformed successful responses', () async {
    status = 200;
    body = '{"header":';
    final result = await ScreenScraperService.verifyCredentials('user', 'pw');
    expect(result.failure, ScreenScraperAuthFailure.unknown);
    expect(requests, 1);
  });
}
