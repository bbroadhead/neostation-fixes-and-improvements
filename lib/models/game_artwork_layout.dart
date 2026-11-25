enum GameArtworkLayout {
  dynamic,
  stacked,
  rows;

  static GameArtworkLayout fromPreference(String? value) =>
      values.where((layout) => layout.name == value).firstOrNull ?? dynamic;
}
