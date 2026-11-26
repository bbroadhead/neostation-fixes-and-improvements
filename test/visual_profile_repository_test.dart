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
    'resolves each game override independently after reopening preferences',
    () async {
      const system = (systemId: 'psp', emulatorId: null);
      await repository.save(
        system,
        const VisualProfile(borderId: 'system-border'),
      );
      await repository.save(
        scope,
        const VisualProfile(shaderId: '@lcd', inheritBorder: true),
      );
      await repository.save(
        system,
        const VisualProfile(borderId: 'game-border', inheritShader: true),
        gameKey: gameKey,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final reopened = VisualProfileRepository(prefs);
      final first = reopened.resolve(
        systemId: scope.systemId,
        emulatorId: scope.emulatorId,
        romPath: gameKey,
      );
      expect(first?.borderId, 'game-border');
      expect(first?.shaderId, '@lcd');
      await reopened.save(
        system,
        const VisualProfile(shaderId: '@none', inheritBorder: true),
        gameKey: gameKey,
      );
      final second = reopened.resolve(
        systemId: scope.systemId,
        emulatorId: scope.emulatorId,
        romPath: gameKey,
      );
      expect(second?.borderId, 'system-border');
      expect(second?.shaderId, '@none');
      await reopened.save(
        scope,
        const VisualProfile(borderId: 'core-game-border', inheritShader: true),
        gameKey: gameKey,
      );
      final third = reopened.resolve(
        systemId: scope.systemId,
        emulatorId: scope.emulatorId,
        romPath: gameKey,
      );
      expect(third?.borderId, 'core-game-border');
      expect(third?.shaderId, '@lcd');
    },
  );

  test(
    'resolves persisted global shader settings when the system has no profile',
    () async {
      await repository.save(
        VisualProfileRepository.globalScope,
        const VisualProfile(
          shaderId: '@crt',
          shaderParameters: {'CURVATURE_X': 0.2},
        ),
      );
      final profile = repository.resolve(
        systemId: scope.systemId,
        emulatorId: scope.emulatorId,
        romPath: gameKey,
      );
      expect(profile?.shaderId, '@crt');
      expect(profile?.shaderParameters, {'CURVATURE_X': 0.2});
      await repository.save(scope, const VisualProfile(shaderId: '@none'));
      expect(
        repository
            .resolve(
              systemId: scope.systemId,
              emulatorId: scope.emulatorId,
              romPath: gameKey,
            )
            ?.shaderId,
        '@none',
      );
    },
  );

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
