import 'dart:convert';

import 'package:neostation/models/visual_profile.dart';
import 'package:test/test.dart';

void main() {
  const system = (systemId: 'psp', emulatorId: null);
  const core = (systemId: 'psp', emulatorId: 'psp.ra.ppsspp');
  const standalone = (systemId: 'psp', emulatorId: 'psp.standalone.ppsspp');

  test('defaults to Sharp & Clean', () {
    expect(
      resolveVisualProfile(systemId: 'psp', emulatorId: core.emulatorId).preset,
      VisualPreset.sharpAndClean,
    );
  });

  test(
    'a core-specific game override takes precedence over system settings',
    () {
      const gameProfile = VisualProfile(shaderId: 'game-shader');
      expect(
        resolveVisualProfile(
          systemId: 'psp',
          emulatorId: core.emulatorId,
          gameProfiles: {core: gameProfile},
          systemProfiles: {core: const VisualProfile(borderId: 'core-border')},
        ),
        same(gameProfile),
      );
    },
  );

  test('skips overrides tied to a different emulator', () {
    const systemProfile = VisualProfile(preset: VisualPreset.enhanced);
    expect(
      resolveVisualProfile(
        systemId: 'psp',
        emulatorId: core.emulatorId,
        gameProfiles: {standalone: const VisualProfile(borderId: 'standalone')},
        systemProfiles: {system: systemProfile},
      ),
      same(systemProfile),
    );
  });

  test(
    'round trips saved adjustments, keeping None independent of shaders',
    () {
      final profile = VisualProfile.fromJson(
        jsonDecode(
          jsonEncode(
            const VisualProfile(
              preset: VisualPreset.custom,
              shaderId: 'sharp',
              size: 0.6,
              horizontal: -0.25,
              vertical: 0.5,
              favoriteBorderIds: {'console'},
              borderPlacements: {
                'console': (size: 0.8, horizontal: 0.1, vertical: -0.1),
              },
            ),
          ),
        ) as Map<String, Object?>,
      );
      expect(profile.preset, VisualPreset.custom);
      expect(profile.shaderId, 'sharp');
      expect(profile.borderId, isNull);
      expect(profile.size, 0.6);
      expect(profile.horizontal, -0.25);
      expect(profile.vertical, 0.5);
      expect(profile.favoriteBorderIds, {'console'});
      expect(profile.borderPlacements['console'], (
        size: 0.8,
        horizontal: 0.1,
        vertical: -0.1,
      ));
    },
  );

  test('handles unknown presets and bounds imported adjustments', () {
    final profile = VisualProfile.fromJson({
      'preset': 'future-preset',
      'size': 5,
      'horizontal': -2,
      'vertical': 'invalid',
    });
    expect(profile.preset, VisualPreset.sharpAndClean);
    expect(profile.size, 1);
    expect(profile.horizontal, -1);
    expect(profile.vertical, 0);
  });
}
