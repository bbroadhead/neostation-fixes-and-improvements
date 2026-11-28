import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../models/artwork_preview.dart';
import '../models/game_model.dart';
import '../utils/atomic_file_writer.dart';

class ArtworkAssignmentService {
  static Future<bool> isReadable(ArtworkPreview image) =>
      isImageReadable(image.bytes);

  static Future<bool> isImageReadable(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        return true;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(
    File target,
    ArtworkPreview image, {
    required bool manual,
  }) async {
    final digest = sha256.convert(image.bytes).toString();
    // A record identifies both the destination and exact bytes. An interrupted
    // replacement or legacy writer cannot make old provenance describe new art.
    final record = provenanceFile(target, digest);
    await writeFileAtomically(
      record,
      utf8.encode(
        jsonEncode({
          'source': image.provider.name,
          'media_type': image.category,
          'assignment_origin': manual ? 'manual' : 'automatic',
        }),
      ),
    );
    if (manual) {
      await replaceManual(target, image.bytes);
    } else {
      await writeFileAtomically(target, image.bytes);
    }
  }

  static Future<void> clearManual(File target) =>
      writeFileAtomically(GameModel.artworkClearMarker(target), const [1]);

  static Future<void> replaceManual(File target, List<int> bytes) async {
    await writeFileAtomically(target, bytes);
    final marker = GameModel.artworkClearMarker(target);
    if (await marker.exists()) await marker.delete();
  }

  static Future<bool> hasManualDecision(File? target) async =>
      target != null &&
      (await target.exists() ||
          await GameModel.artworkClearMarker(target).exists());

  static Future<({ArtworkProvider source, bool manual})?> readProvenance(
    File target,
    String category,
  ) async {
    try {
      final digest = await sha256.bind(target.openRead()).first;
      final record = jsonDecode(
        await provenanceFile(target, digest.toString()).readAsString(),
      );
      if (record is! Map ||
          record['media_type'] != category ||
          !const {
            'manual',
            'automatic',
          }.contains(record['assignment_origin'])) {
        return null;
      }
      final source = ArtworkProvider.values.asNameMap()[record['source']];
      if (source == null) return null;
      return (source: source, manual: record['assignment_origin'] == 'manual');
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static File provenanceFile(File target, String digest) {
    final key = sha256.convert(
      utf8.encode('${path.basename(target.path)}:$digest'),
    );
    return File(path.join(target.parent.path, '.provenance', '$key.json'));
  }
}
