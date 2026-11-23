/// The Genesis hacks definition predates the current folder naming convention.
/// Its database ID must stay stable so existing ROM rows retain their ownership.
String systemDefinitionId(String systemId) =>
    systemId == 'gen-hacks' ? 'genesis-hacks' : systemId;

/// Hacks keep their library identity and use the corresponding console.
String parentSystemId(String systemId) {
  final definition = systemDefinitionId(systemId);
  return definition.endsWith('-hacks')
      ? definition.substring(0, definition.length - '-hacks'.length)
      : systemId;
}

/// Retains the existing child identifier namespace for per-game overrides.
String emulatorIdForSystem(String emulatorId, String from, String to) {
  if (from == to) return emulatorId;
  final prefix = systemDefinitionId(from);
  final suffix = emulatorId.startsWith('$prefix.')
      ? emulatorId.substring(prefix.length + 1)
      : emulatorId;
  return '${systemDefinitionId(to)}.$suffix';
}
