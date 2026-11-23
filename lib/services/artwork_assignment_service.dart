import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../models/artwork_preview.dart';
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
    await writeFileAtomically(target, image.bytes);
  }

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
