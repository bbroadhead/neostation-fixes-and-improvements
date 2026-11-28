enum GameArtworkLayout {
  dynamic,
  stacked,
  fan;

  static GameArtworkLayout fromPreference(String? value) => value == 'rows'
      ? fan
      : values.where((layout) => layout.name == value).firstOrNull ?? dynamic;
}
