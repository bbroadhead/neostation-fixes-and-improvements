import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/services/ra_guide_service.dart';

void main() {
  test(
    'selects the dedicated guide for the exact RetroAchievements ID',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/RetroAchievements/guides/wiki/SNES');
        return http.Response('''
        <tr><td><a href="https://evil.example/guide">Outside</a>
        <a href="/RetroAchievements/guides/wiki/Guide-228">Guide</a></td>
        <td><a href="https://retroachievements.org/game/228">228</a></td></tr>
        <tr><td><a href="/RetroAchievements/guides/wiki/Guide-2280">Guide</a></td>
        <td><a href="https://retroachievements.org/game/2280">2280</a></td></tr>
      ''', 200);
      });
      expect(
        await RaGuideService.resolve(228, 'snes-hacks', client: client),
        Uri.parse('https://github.com/RetroAchievements/guides/wiki/Guide-228'),
      );
      expect(
        await RaGuideService.resolve(22, 'snes', client: client),
        Uri.parse('https://retroachievements.org/game/22'),
      );
    },
  );

  test('keeps the game page as a fallback during an outage', () async {
    final client = MockClient((_) async => http.Response('', 503));
    expect(
      await RaGuideService.resolve(228, 'snes', client: client),
      Uri.parse('https://retroachievements.org/game/228'),
    );
  });
}
