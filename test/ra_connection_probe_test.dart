import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/services/retro_achievements_service.dart';

void main() {
  test(
    'classifies current network, authentication and service responses',
    () async {
      for (final (status, body, expected) in [
        (200, '{"User":"player"}', RaConnectionStatus.available),
        (200, 'invalid', RaConnectionStatus.serviceUnavailable),
        (401, '', RaConnectionStatus.authorizationFailed),
        (403, '', RaConnectionStatus.authorizationFailed),
        (503, '', RaConnectionStatus.serviceUnavailable),
      ]) {
        final client = MockClient((_) async => http.Response(body, status));
        expect(
          await RetroAchievementsService.probeConnection(
            'player',
            'fixture-key',
            client: client,
          ),
          expected,
        );
      }
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      expect(
        await RetroAchievementsService.probeConnection(
          'player',
          'fixture-key',
          client: client,
        ),
        RaConnectionStatus.networkUnavailable,
      );
    },
  );
}
