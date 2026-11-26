import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/ra_compatibility.dart';
import 'package:neostation/repositories/retro_achievements_repository.dart';
import 'package:neostation/services/retroachievements_hash_service.dart';
import 'package:neostation/services/user_data_location_service.dart';
import 'package:neostation/utils/optimized_md5_utils.dart';

import 'database_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final payload = [255, 254, 0, 128, 17, ...List<int>.generate(100, (i) => i)];
  final header = [0x4c, 0x59, 0x4e, 0x58, 0, ...List<int>.filled(59, 0)];
  // Synthetic fixture digests from rcheevos 094616b, console 13.
  const payloadHash = '2442fc2f9bb93ea1bd3d11cbbeee4892';
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('neostation_lynx_hash_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('uses the binary Lynx header rule for raw ROMs', () async {
    for (final (filename, bytes, expected) in [
      ('headered.lnx', [...header, ...payload], payloadHash),
      ('raw.lnx', payload, payloadHash),
      ('raw.lyx', payload, payloadHash),
      ('raw.bll', payload, payloadHash),
      ('raw.o', payload, payloadHash),
      ('exactly-64.lnx', header, 'a6684f8dc16180ca480a5d40420e567e'),
      (
        'wrong-magic.lnx',
        [...header.sublist(0, 4), 1, ...header.sublist(5), ...payload],
        'e382071f550d61b1cf6aa43f6a17cc22',
      ),
    ]) {
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      expect(await OptimizedMd5Utils.calculateLynxMd5(file.path), expected);
    }
  });

  test(
    'bulk matching retries legacy Lynx failures using the archive ROM',
    () async {
      final database = DatabaseTestHelper();
      final db = await database.setUp();
      addTearDown(database.tearDown);
      await UserDataLocationService.setCustomPath(dir.path);
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, ra_id, ra_hash_algo, ra_hash_mode) "
        "VALUES ('lynx', 'Atari Lynx', 'lynx', '13', 'lynx', 'hash_only'), "
        "('nes', 'NES', 'nes', '7', 'nes', 'hash_only')",
      );
      final rom = File('${dir.path}/fixture.zip');
      final archive = Archive()
        ..addFile(ArchiveFile('guide.txt', 500, List<int>.filled(500, 97)))
        ..addFile(ArchiveFile('cartridge.LYX', payload.length, payload));
      await rom.writeAsBytes(ZipEncoder().encode(archive));
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash_skipped) "
        "VALUES ('fixture.zip', ?, 'lynx', 'error'), "
        "('other.nes', '/fixture/other.nes', 'nes', 'error'), "
        "('parked.zip', '/fixture/parked.zip', 'lynx', 'lynx_hash_error')",
        [rom.path],
      );
      await db.execute(
        "INSERT INTO app_ra_game_list (game_id, title, console_id, hash, num_achievements) "
        "VALUES (112233, 'Synthetic catalogue fixture', '13', ?, 1)",
        [payloadHash],
      );

      final result = await RetroAchievementsHashService.rematchLibrary(
        reopenSkipped: false,
      );
      expect(result.total, 1);
      expect(result.hashed, 1);
      expect(result.matched, 1);
      expect(
        await RetroAchievementsRepository.getRomRaHash(rom.path),
        payloadHash,
      );
      final compatibility =
          await RetroAchievementsRepository.getRomCompatibility(rom.path);
      expect(compatibility.status, RaCompatibilityStatus.supported);
      expect(compatibility.gameId, 112233);
      expect(await RetroAchievementsRepository.getRaHashSkipCounts(), {
        'error': 1,
        'lynx_hash_error': 1,
      });
      expect(
        await Directory('${dir.path}/temp/lynx/fixture.zip').exists(),
        isFalse,
      );
    },
  );
}
