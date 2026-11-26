/// The user's choice for an already-resolved emulator launch.
enum VisualPreset { sharpAndClean, enhanced, authentic, custom }

typedef BorderPlacement = ({double size, double horizontal, double vertical});

typedef VisualProfileScope = ({String systemId, String? emulatorId});

class VisualProfile {
  const VisualProfile({
    this.preset = VisualPreset.sharpAndClean,
    this.borderId,
    this.shaderId,
    this.shaderParameters = const {},
    this.size = 1,
    this.horizontal = 0,
    this.vertical = 0,
    this.borderPlacements = const {},
    this.favoriteBorderIds = const {},
  });

  final VisualPreset preset;
  final String? borderId;
  final String? shaderId;
  final Map<String, double> shaderParameters;
  final double size;
  final double horizontal;
  final double vertical;
  final Map<String, BorderPlacement> borderPlacements;
  final Set<String> favoriteBorderIds;

  factory VisualProfile.fromJson(Map<String, Object?> json) {
    final preset = VisualPreset.values.asNameMap()[json['preset']];
    return VisualProfile(
      preset: preset ?? VisualPreset.sharpAndClean,
      borderId: _id(json['borderId']),
      shaderId: _id(json['shaderId']),
      shaderParameters: switch (json['shaderParameters']) {
        final Map<String, Object?> parameters => Map.unmodifiable({
          for (final entry in parameters.entries)
            if (entry.value case final num value when value.isFinite)
              entry.key: value.toDouble(),
        }),
        _ => const {},
      },
      size: _bounded(json['size'], 0, 1, 1),
      horizontal: _bounded(json['horizontal'], -1, 1, 0),
      vertical: _bounded(json['vertical'], -1, 1, 0),
      borderPlacements: _placementsFromJson(json['borderPlacements']),
      favoriteBorderIds: switch (json['favoriteBorderIds']) {
        final List<Object?> ids => Set.unmodifiable(ids.whereType<String>()),
        _ => const {},
      },
    );
  }

  Map<String, Object?> toJson() => {
    'preset': preset.name,
    'borderId': borderId,
    'shaderId': shaderId,
    if (shaderParameters.isNotEmpty) 'shaderParameters': shaderParameters,
    'size': size,
    'horizontal': horizontal,
    'vertical': vertical,
    'favoriteBorderIds': favoriteBorderIds.toList(),
    'borderPlacements': {
      for (final entry in borderPlacements.entries)
        entry.key: {
          'size': entry.value.size,
          'horizontal': entry.value.horizontal,
          'vertical': entry.value.vertical,
        },
    },
  };

  static Map<String, BorderPlacement> _placementsFromJson(Object? json) {
    if (json is! Map<String, Object?>) return const {};
    final placements = <String, BorderPlacement>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is Map<String, Object?>) {
        placements[entry.key] = (
          size: _bounded(value['size'], 0.25, 1, 1),
          horizontal: _bounded(value['horizontal'], -1, 1, 0),
          vertical: _bounded(value['vertical'], -1, 1, 0),
        );
      }
    }
    return Map.unmodifiable(placements);
  }

  static String? _id(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static double _bounded(Object? value, num min, num max, double fallback) =>
      value is num && value.isFinite
      ? value.clamp(min, max).toDouble()
      : fallback;
}

/// The caller supplies the persisted profiles for the selected game and
/// system. Profiles scoped to other emulators cannot affect this launch.
VisualProfile resolveVisualProfile({
  required String systemId,
  required String emulatorId,
  Map<VisualProfileScope, VisualProfile> systemProfiles = const {},
  Map<VisualProfileScope, VisualProfile> gameProfiles = const {},
}) {
  final emulator = (systemId: systemId, emulatorId: emulatorId);
  final system = (systemId: systemId, emulatorId: null);
  return gameProfiles[emulator] ??
      gameProfiles[system] ??
      systemProfiles[emulator] ??
      systemProfiles[system] ??
      const VisualProfile();
}
