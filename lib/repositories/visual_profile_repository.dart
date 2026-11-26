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
    return resolveWithOrigins(
      systemId: systemId,
      emulatorId: emulatorId,
      romPath: romPath,
    )?.profile;
  }

  ({
    VisualProfile profile,
    VisualProfileScope? borderScope,
    VisualProfileScope? shaderScope,
  })?
  resolveWithOrigins({
    required String systemId,
    required String? emulatorId,
    String? romPath,
  }) {
    final system = (systemId: systemId, emulatorId: null);
    final emulator = (systemId: systemId, emulatorId: emulatorId);
    final choices = [
      if (romPath != null) ...[
        (emulator, romPath),
        if (emulator != system) (system, romPath),
      ],
      (emulator, null),
      if (emulator != system) (system, null),
      (globalScope, null),
    ];
    VisualProfile? border;
    VisualProfile? shader;
    VisualProfileScope? borderScope;
    VisualProfileScope? shaderScope;
    var found = false;
    var foundGame = false;
    for (final (scope, gameKey) in choices) {
      if (gameKey != null && foundGame) continue;
      final profile = read(scope, gameKey: gameKey);
      if (profile == null) continue;
      if (gameKey != null) foundGame = true;
      found = true;
      if (border == null && !profile.inheritBorder) {
        border = profile;
        borderScope = scope;
      }
      if (shader == null && !profile.inheritShader) {
        shader = profile;
        shaderScope = scope;
      }
      if (border != null && shader != null) break;
    }
    if (!found) return null;
    return (
      profile: combineVisualSettings(
        border: border ?? const VisualProfile(),
        shader: shader ?? const VisualProfile(),
      ),
      borderScope: borderScope,
      shaderScope: shaderScope,
    );
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
