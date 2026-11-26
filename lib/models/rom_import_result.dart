enum RomImportStage { discovering, checkingDuplicates, saving }

class RomImportResult {
  const RomImportResult({
    this.discovered = 0,
    this.added = 0,
    this.existing = 0,
    this.duplicates = 0,
    this.cancelled = false,
    this.unsupported = 0,
    this.playlistDiscs = 0,
    this.failures = const [],
    this.walkError,
    this.elapsed = Duration.zero,
  });

  final int discovered;
  final int added;

  /// Existing paths and newly skipped duplicate files, for legacy callers.
  final int existing;
  final int duplicates;
  final bool cancelled;
  final int unsupported;
  final int playlistDiscs;
  final List<String> failures;
  final String? walkError;
  final Duration elapsed;

  bool get hasErrors => failures.isNotEmpty || walkError != null;
}
