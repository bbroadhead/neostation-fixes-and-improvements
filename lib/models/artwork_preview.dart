import 'dart:typed_data';

enum ArtworkProvider {
  neoAssets('NeoAssets'),
  steamGridDb('SteamGridDB'),
  retroAchievements('RetroAchievements'),
  libretro('Libretro'),
  screenScraper('ScreenScraper');

  const ArtworkProvider(this.displayName);

  final String displayName;
}

typedef ArtworkPreview = ({
  ArtworkProvider provider,
  String category,
  String title,
  Uint8List bytes,
});
