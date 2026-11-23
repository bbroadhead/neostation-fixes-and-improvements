class RomImportResult {
  const RomImportResult({
    this.discovered = 0,
    this.added = 0,
    this.existing = 0,
    this.unsupported = 0,
    this.playlistDiscs = 0,
    this.failures = const [],
    this.walkError,
    this.elapsed = Duration.zero,
  });

  final int discovered;
  final int added;
  final int existing;
  final int unsupported;
  final int playlistDiscs;
  final List<String> failures;
  final String? walkError;
  final Duration elapsed;

  bool get hasErrors => failures.isNotEmpty || walkError != null;
}
