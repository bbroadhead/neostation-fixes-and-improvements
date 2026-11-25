import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/visual_profile.dart';
import 'package:neostation/repositories/visual_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scope = (systemId: 'psp', emulatorId: 'psp.ra.ppsspp');
  const gameKey = 'library/PSP/Game.iso';
  late VisualProfileRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = VisualProfileRepository(await SharedPreferences.getInstance());
  });

  test(
    'persists settings and resets the game without removing core settings',
    () async {
      expect(
        await repository.save(scope, const VisualProfile(borderId: 'console')),
        isTrue,
      );
      expect(
        await repository.save(
          scope,
          const VisualProfile(shaderId: 'sharp', size: 0.6),
          gameKey: gameKey,
        ),
        isTrue,
      );

      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final reopened = VisualProfileRepository(preferences);
      expect(reopened.read(scope, gameKey: gameKey)?.shaderId, 'sharp');
      expect(reopened.read(scope, gameKey: gameKey)?.size, 0.6);
      expect(reopened.read(scope)?.borderId, 'console');

      expect(await reopened.reset(scope, gameKey: gameKey), isTrue);
      expect(reopened.read(scope, gameKey: gameKey), isNull);
      expect(reopened.read(scope)?.borderId, 'console');
    },
  );
}
