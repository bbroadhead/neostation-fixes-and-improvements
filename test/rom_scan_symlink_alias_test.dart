import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_database_service.dart';
import 'package:neostation/models/system_model.dart';

import 'database_test_helper.dart';

/// EmuDeck ships alias directories as symlinks (roms/gamecube -> roms/gc), and
/// both names are registered folders of the same system, so an unguarded scan
/// finds every file twice and stores it under two rom_path spellings.
void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  const gcSystem = SystemModel(
    id: 'gc',
    realName: 'Nintendo GameCube',
    folderName: 'gc',
    iconImage: '',
    color: '#000000',
    recursiveScan: true,
  );

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('gc', 'Nintendo GameCube', 'gc')",
    );
    await db.execute(
      "INSERT INTO app_system_extensions (system_id, extension) VALUES ('gc', 'rvz')",
    );
    for (final alias in ['GameCube', 'Nintendo GameCube', 'gc', 'ngc']) {
      await db.rawInsert(
        'INSERT INTO app_system_folders (system_id, folder_name) VALUES (?, ?)',
        ['gc', alias],
      );
    }
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  /// Builds `<root>/gc` holding [filenames], plus a `<root>/gamecube` symlink
  /// pointing at it, mirroring an EmuDeck layout.
  Future<Directory> createAliasedRomTree(List<String> filenames) async {
    final root = await Directory.systemTemp.createTemp('neostation_symlink_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final real = Directory('${root.path}/gc')..createSync(recursive: true);
    for (final name in filenames) {
      File('${real.path}/$name').writeAsStringSync('rom');
    }
    Link('${root.path}/gamecube').createSync(real.path);
    return root;
  }

  Future<List<Map<String, Object?>>> romRows() async {
    return await db.rawQuery(
      "SELECT filename, rom_path, is_favorite, play_time, last_played, id_ra "
      "FROM user_roms WHERE app_system_id = 'gc' ORDER BY rom_path",
    );
  }

  group('ROM scan across symlinked alias folders', () {
    test('stores one row per physical file, at the real path', () async {
      final root = await createAliasedRomTree(['18 Wheeler.rvz']);

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows, hasLength(1));
      expect(rows.single['rom_path'], '${root.path}/gc/18 Wheeler.rvz');
    });

    test('still scans an alias that is a real directory of its own', () async {
      final root = await Directory.systemTemp.createTemp('neostation_symlink_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      Directory('${root.path}/gc').createSync(recursive: true);
      Directory('${root.path}/ngc').createSync(recursive: true);
      File('${root.path}/gc/A.rvz').writeAsStringSync('rom');
      File('${root.path}/ngc/B.rvz').writeAsStringSync('rev');

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows.map((r) => r['filename']), ['A.rvz', 'B.rvz']);
    });

    test(
      'skips byte-identical copies and keeps the familiar path on rescan',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'neostation_copies_',
        );
        addTearDown(() => root.delete(recursive: true));
        final folder = await Directory('${root.path}/gc').create();
        final original = await File('${folder.path}/Z Original.rvz')
            .writeAsString('abc');
        await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);
        await db.execute(
          'UPDATE user_roms SET is_favorite = 1 WHERE rom_path = ?',
          [original.path],
        );

        final copies = await Directory('${folder.path}/Copies').create();
        await original.copy('${copies.path}/A Copy.rvz');
        await original.copy('${copies.path}/B Copy.rvz');
        await File('${copies.path}/Revision.rvz').writeAsString('xyz');
        final scan = await SqliteDatabaseService.scanSystemRoms(gcSystem, [
          root.path,
        ]);
        expect(scan.added, 1);
        expect(scan.removed, 0);
        final rows = await romRows();
        expect(
          rows.map((row) => row['filename']),
          unorderedEquals(['Z Original.rvz', 'Revision.rvz']),
        );
        expect(
          rows.singleWhere(
            (row) => row['rom_path'] == original.path,
          )['is_favorite'],
          1,
        );
        expect(await File('${copies.path}/A Copy.rvz').exists(), isTrue);
        expect(
          (await SqliteDatabaseService.scanSystemRoms(gcSystem, [
            root.path,
          ])).added,
          0,
        );
      },
    );

    test('fresh scan indexes one deterministic copy', () async {
      final root = await createAliasedRomTree(['B.rvz', 'A.rvz']);
      final scan = await SqliteDatabaseService.scanSystemRoms(gcSystem, [
        root.path,
      ]);
      expect(scan.added, 1);
      expect((await romRows()).single['filename'], 'A.rvz');
    });

    test(
      'keeps identical launcher scripts that run in different directories',
      () async {
        await db.execute(
          "INSERT INTO app_system_extensions (system_id, extension) VALUES ('gc', 'sh')",
        );
        final root = await createAliasedRomTree([]);
        for (final title in ['A', 'B']) {
          final folder = await Directory('${root.path}/gc/$title').create();
          await File('${folder.path}/run.sh').writeAsString('./game');
        }
        final scan = await SqliteDatabaseService.scanSystemRoms(gcSystem, [
          root.path,
        ]);
        expect(scan.added, 2);
      },
    );

    test(
      'identical disc descriptors can reference different local tracks',
      () async {
        await db.execute(
          "INSERT INTO app_system_extensions (system_id, extension) VALUES ('gc', 'cue')",
        );
        final root = await createAliasedRomTree([]);
        for (final disc in ['Disc A', 'Disc B']) {
          final folder = await Directory('${root.path}/gc/$disc').create();
          await File('${folder.path}/game.cue')
              .writeAsString('FILE "track.bin" BINARY');
          await File('${folder.path}/track.bin').writeAsString(disc);
        }
        final scan = await SqliteDatabaseService.scanSystemRoms(gcSystem, [
          root.path,
        ]);
        expect(scan.added, 2);
        expect((await romRows()).map((row) => row['filename']), [
          'game.cue',
          'game.cue',
        ]);
      },
    );

    test(
      'keeps the real directory when the primary folder is the link',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'neostation_symlink_',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });

        // Reversed layout: the alias is the real directory, `gc` links to it.
        final real = Directory('${root.path}/gamecube')
          ..createSync(recursive: true);
        File('${real.path}/Wave Race.rvz').writeAsStringSync('rom');
        Link('${root.path}/gc').createSync(real.path);

        await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

        final rows = await romRows();
        expect(rows, hasLength(1));
        expect(rows.single['rom_path'], '${real.path}/Wave Race.rvz');
      },
    );

    test('deduplicates files held in subdirectories', () async {
      final root = await Directory.systemTemp.createTemp('neostation_symlink_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final sub = Directory('${root.path}/gc/Multi Disc')
        ..createSync(recursive: true);
      File('${sub.path}/Baten Kaitos.rvz').writeAsStringSync('rom');
      Link('${root.path}/gamecube').createSync('${root.path}/gc');

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      expect(await romRows(), hasLength(1));
    });
  });

  group('Existing duplicate rows', () {
    test('merges the alias row user data into the surviving row', () async {
      final root = await createAliasedRomTree(['18 Wheeler.rvz']);
      final realPath = '${root.path}/gc/18 Wheeler.rvz';
      final aliasPath = '${root.path}/gamecube/18 Wheeler.rvz';

      // The pre-fix state: both spellings stored, and the alias row is the one
      // carrying the play time, the favourite flag and the scraped id.
      await db.rawInsert(
        'INSERT INTO user_roms (app_system_id, filename, rom_path, is_favorite, play_time) '
        "VALUES ('gc', '18 Wheeler.rvz', ?, 0, 120)",
        [realPath],
      );
      await db.rawInsert(
        'INSERT INTO user_roms (app_system_id, filename, rom_path, is_favorite, play_time, last_played, id_ra) '
        "VALUES ('gc', '18 Wheeler.rvz', ?, 1, 3600, '2026-08-01T10:00:00Z', 4242)",
        [aliasPath],
      );

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['rom_path'], realPath);
      expect(row['is_favorite'], 1);
      expect(row['play_time'], 3720); // Each launch hit exactly one row.
      expect(row['last_played'], '2026-08-01T10:00:00Z');
      expect(row['id_ra'], 4242);
    });

    test('adopts the alias row when no row exists at the real path', () async {
      final root = await createAliasedRomTree(['18 Wheeler.rvz']);
      final aliasPath = '${root.path}/gamecube/18 Wheeler.rvz';

      await db.rawInsert(
        'INSERT INTO user_roms (app_system_id, filename, rom_path, is_favorite, play_time, id_ra) '
        "VALUES ('gc', '18 Wheeler.rvz', ?, 1, 900, 77)",
        [aliasPath],
      );

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows, hasLength(1));
      expect(rows.single['rom_path'], '${root.path}/gc/18 Wheeler.rvz');
      expect(rows.single['is_favorite'], 1);
      expect(rows.single['play_time'], 900);
      expect(rows.single['id_ra'], 77);
    });

    test('still removes rows whose file is genuinely gone', () async {
      final root = await createAliasedRomTree(['18 Wheeler.rvz']);

      await db.rawInsert(
        'INSERT INTO user_roms (app_system_id, filename, rom_path, play_time) '
        "VALUES ('gc', 'Deleted.rvz', ?, 500)",
        ['${root.path}/gc/Deleted.rvz'],
      );

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows.map((r) => r['filename']), ['18 Wheeler.rvz']);
    });
  });
}
