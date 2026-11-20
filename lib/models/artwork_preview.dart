import 'dart:typed_data';

enum ArtworkProvider {
  steamGridDb('SteamGridDB'),
  retroAchievements('RetroAchievements'),
  libretro('Libretro');

  const ArtworkProvider(this.displayName);

  final String displayName;
}

typedef ArtworkPreview = ({
  ArtworkProvider provider,
  String category,
  String title,
  Uint8List bytes,
});
