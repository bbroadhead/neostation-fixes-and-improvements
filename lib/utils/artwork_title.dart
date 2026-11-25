/// Title comparison for artwork lookups. Preserve hack and translation
/// qualifiers while removing known dump metadata from the end of a filename.
class ArtworkTitle {
  static final _dumpSuffix = RegExp(
    r'(?:\s*\[(?:!|c|[abfhopt][0-9]+)\]|\s*\((?:'
    r'(?:U|E|J|USA|Europe|Japan|World|Australia|Canada|Korea|China|Brazil|Asia)'
    r'(?:,\s*(?:USA|Europe|Japan|World|Australia|Canada|Korea|China|Brazil|Asia))*'
    r'|SGB Enhanced|GB Compatible|Rev\s+[0-9a-z.]+|Disc\s+\d+|Side\s+[AB]|'
    r'(?:En|Fr|De|Es|It|Ja|Pt|Zh|Ko)(?:,\s*(?:En|Fr|De|Es|It|Ja|Pt|Zh|Ko))*'
    r')\))+$',
    caseSensitive: false,
  );

  static String clean(String title) =>
      title.trim().replaceFirst(_dumpSuffix, '').trim();

  static String normalized(String title) =>
      clean(title)
          .toLowerCase()
          .replaceAll(RegExp(r"['’]"), '')
          .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
          .trim();

  static Set<String> queries(String title) {
    final cleanTitle = clean(title);
    if (cleanTitle.isEmpty) return const {};
    final alternate = cleanTitle.replaceFirstMapped(
      RegExp(r'^Dragon (Quest|Warrior)\b', caseSensitive: false),
      (match) => match[1]!.toLowerCase() == 'quest'
          ? 'Dragon Warrior'
          : 'Dragon Quest',
    );
    return {
      cleanTitle,
      cleanTitle.replaceFirst(RegExp(r'\s+-\s+'), ': '),
      alternate,
      alternate.replaceFirst(RegExp(r'\s+-\s+'), ': '),
    };
  }
}
