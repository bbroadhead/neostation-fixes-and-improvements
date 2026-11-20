enum ArtworkScrapeEvent {
  downloaded,
  assigned,
  skippedManual,
  unavailable,
  failed,
}

typedef ArtworkScrapeObserver = void Function(
  String category,
  ArtworkScrapeEvent event,
);

typedef ScrapeIssue = ({
  String romPath,
  String name,
  Map<String, ArtworkScrapeEvent> categories,
  bool gameFailed,
});
