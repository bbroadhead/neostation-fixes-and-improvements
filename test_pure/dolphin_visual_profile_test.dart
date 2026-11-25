import 'package:neostation/models/visual_profile.dart';
import 'package:neostation/services/visual_profiles/dolphin_visual_profile.dart';
import 'package:test/test.dart';

void main() {
  const arguments = ['-b', '-e', '/roms/Game with spaces.iso'];

  test('scales rendering without changing the boot arguments', () {
    for (final (preset, scale) in [
      (VisualPreset.sharpAndClean, 2),
      (VisualPreset.enhanced, 3),
      (VisualPreset.authentic, 1),
    ]) {
      expect(
        DolphinVisualProfile.arguments(
          arguments,
          VisualProfile(preset: preset),
        ),
        ['-C', 'GFX.Settings.InternalResolution=$scale', ...arguments],
      );
    }
  });

  test('respects custom engine settings and explicit command-line config', () {
    expect(
      DolphinVisualProfile.arguments(
        arguments,
        const VisualProfile(preset: VisualPreset.custom),
      ),
      same(arguments),
    );
    final explicit = [
      '--config=GFX.Settings.InternalResolution=4',
      ...arguments,
    ];
    expect(
      DolphinVisualProfile.arguments(explicit, const VisualProfile()),
      same(explicit),
    );
  });

  test(
    'does not opt Dolphin forks or the libretro core into standalone flags',
    () {
      expect(
        DolphinVisualProfile.supports('gc.org.dolphinemu.dolphinemu'),
        isTrue,
      );
      expect(
        DolphinVisualProfile.supports('wii.org.dolphinemu.dolphinemu'),
        isTrue,
      );
      expect(DolphinVisualProfile.supports('gc.primehack'), isFalse);
      expect(DolphinVisualProfile.supports('gc.ra.dolphin'), isFalse);
    },
  );
}
