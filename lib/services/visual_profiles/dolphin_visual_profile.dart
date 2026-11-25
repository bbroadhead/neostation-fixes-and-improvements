import '../../models/visual_profile.dart';

/// Dolphin's command-line configuration layer applies for one invocation.
class DolphinVisualProfile {
  const DolphinVisualProfile._();

  static bool supports(String? id) =>
      id == 'gc.org.dolphinemu.dolphinemu' ||
      id == 'wii.org.dolphinemu.dolphinemu';

  static List<String> arguments(List<String> original, VisualProfile profile) {
    if (original.any(
      (arg) =>
          arg == '--' ||
          arg.startsWith('-C') ||
          arg == '--config' ||
          arg.startsWith('--config='),
    )) {
      return original;
    }
    final resolution = switch (profile.preset) {
      VisualPreset.sharpAndClean => 2,
      VisualPreset.enhanced => 3,
      VisualPreset.authentic => 1,
      VisualPreset.custom => null,
    };
    return resolution == null
        ? original
        : ['-C', 'GFX.Settings.InternalResolution=$resolution', ...original];
  }
}
