import 'dart:typed_data';

enum ArtworkProvider { retroAchievements, libretro }

typedef ArtworkPreview = ({
  ArtworkProvider provider,
  String category,
  String title,
  Uint8List bytes,
});
