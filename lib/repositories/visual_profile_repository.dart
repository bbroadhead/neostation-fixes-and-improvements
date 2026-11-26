import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/visual_profile.dart';

/// Stores independently editable scopes. A game key is its stable library
/// identity, supplied by the caller.
class VisualProfileRepository {
  VisualProfileRepository(this._preferences);

  static const VisualProfileScope globalScope = (
    systemId: ':global:',
    emulatorId: null,
  );

  final SharedPreferences _preferences;

  VisualProfile? read(VisualProfileScope scope, {String? gameKey}) {
    final encoded = _preferences.get(_key(scope, gameKey));
    if (encoded is! String) return null;
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, Object?>
          ? VisualProfile.fromJson(decoded)
          : null;
    } on FormatException {
      return null;
    }
  }

  VisualProfile? resolve({
    required String systemId,
    required String? emulatorId,
    required String? romPath,
  }) {
    final system = (systemId: systemId, emulatorId: null);
    final emulator = (systemId: systemId, emulatorId: emulatorId);
    return (romPath == null ? null : read(emulator, gameKey: romPath)) ??
        (romPath == null || emulator == system
            ? null
            : read(system, gameKey: romPath)) ??
        read(emulator) ??
        (emulator == system ? null : read(system)) ??
        read(globalScope);
  }

  Future<bool> save(
    VisualProfileScope scope,
    VisualProfile profile, {
    String? gameKey,
  }) => _preferences.setString(
    _key(scope, gameKey),
    jsonEncode(profile.toJson()),
  );

  Future<bool> reset(VisualProfileScope scope, {String? gameKey}) =>
      _preferences.remove(_key(scope, gameKey));

  static String _key(VisualProfileScope scope, String? gameKey) =>
      'visualProfiles.v1.${jsonEncode([scope.systemId, scope.emulatorId, gameKey])}';
}
