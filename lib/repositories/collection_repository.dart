import '../data/datasources/sqlite_service.dart';
import '../models/database_game_model.dart';

/// Repository for user-defined collections (`user_collections` /
/// `user_collection_items`).
///
/// Thin static delegation to [SqliteService], mirroring `SystemRepository` and
/// `GameRepository`: this is the only layer permitted to reach the datasource,
/// so `CollectionsService` and everything above it goes through here.
class CollectionRepository {
  const CollectionRepository._();

  static const retroAchievementsIncompatibleId =
      '44ec1024-90ab-4edf-9071-0bcb2ed89725';

  /// Atomically replaces membership for the generated collection using its
  /// reserved id. User collections can have the same display name.
  static Future<bool> updateRetroAchievementsIncompatible(
    Set<String> romPaths,
  ) async {
    final db = await SqliteService.getDatabase();
    const id = retroAchievementsIncompatibleId;
    const name = 'RetroAchievements Incompatible';
    return db.transaction((txn) async {
      final collections = await txn.rawQuery(
        'SELECT name FROM user_collections WHERE id = ?',
        [id],
      );
      if (collections.isEmpty) {
        await txn.rawInsert(
          '''
          INSERT INTO user_collections (id, name, sort_order)
          SELECT ?, ?, COALESCE(MAX(sort_order), -1) + 1 FROM user_collections
        ''',
          [id, name],
        );
      }
      final before = await txn.rawQuery(
        'SELECT rom_path FROM user_collection_items WHERE collection_id = ?',
        [id],
      );
      if (collections.isNotEmpty &&
          collections.first['name'] == name &&
          before.length == romPaths.length &&
          before.every((row) => romPaths.contains(row['rom_path']))) {
        return false;
      }
      final batch = txn.batch();
      batch.rawUpdate(
        'UPDATE user_collections SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
        [name, id],
      );
      batch.rawDelete(
        'DELETE FROM user_collection_items WHERE collection_id = ?',
        [id],
      );
      for (final (order, path) in romPaths.indexed) {
        batch.rawInsert(
          '''
          INSERT INTO user_collection_items (collection_id, rom_path, sort_order)
          SELECT ?, rom_path, ? FROM user_roms WHERE rom_path = ?
        ''',
          [id, order, path],
        );
      }
      await batch.commit(noResult: true);
      return true;
    });
  }

  /// Returns every collection row with its membership count.
  static Future<List<Map<String, Object?>>> getCollections() =>
      SqliteService.getCollections();

  /// Returns one collection row (with its game count), or null.
  static Future<Map<String, Object?>?> getCollectionById(String id) =>
      SqliteService.getCollectionById(id);

  /// Inserts a collection with a caller-supplied [id].
  static Future<void> insertCollection({
    required String id,
    required String name,
    String? imagePath,
    String? color1,
    String? color2,
    int? sortOrder,
    String? rulesJson,
  }) => SqliteService.insertCollection(
    id: id,
    name: name,
    imagePath: imagePath,
    color1: color1,
    color2: color2,
    sortOrder: sortOrder,
    rulesJson: rulesJson,
  );

  /// Updates a collection's mutable fields.
  static Future<void> updateCollection(
    String id, {
    String? name,
    String? imagePath,
    bool clearImagePath = false,
    String? color1,
    bool clearColor1 = false,
    String? color2,
    bool clearColor2 = false,
    int? sortOrder,
    String? rulesJson,
  }) => SqliteService.updateCollection(
    id,
    name: name,
    imagePath: imagePath,
    clearImagePath: clearImagePath,
    color1: color1,
    clearColor1: clearColor1,
    color2: color2,
    clearColor2: clearColor2,
    sortOrder: sortOrder,
    rulesJson: rulesJson,
  );

  /// Deletes a collection and its membership rows.
  static Future<void> deleteCollection(String id) =>
      SqliteService.deleteCollection(id);

  /// Adds a ROM to a collection. Re-adding is a no-op.
  static Future<void> addRomToCollection(String collectionId, String romPath) =>
      SqliteService.addRomToCollection(collectionId, romPath);

  /// Removes a ROM from a collection. Removing a non-member is a no-op.
  static Future<void> removeRomFromCollection(
    String collectionId,
    String romPath,
  ) => SqliteService.removeRomFromCollection(collectionId, romPath);

  /// Returns the ids of every collection containing [romPath].
  static Future<List<String>> getCollectionIdsForRom(String romPath) =>
      SqliteService.getCollectionIdsForRom(romPath);

  static Future<Map<String, Set<String>>> getMemberPathsByCollection() async {
    final db = await SqliteService.getDatabase();
    final rows = await db.rawQuery(
      'SELECT collection_id, rom_path FROM user_collection_items',
    );
    final paths = <String, Set<String>>{};
    for (final row in rows) {
      paths
          .putIfAbsent(row['collection_id'].toString(), () => {})
          .add(row['rom_path'].toString());
    }
    return paths;
  }

  /// Returns the games in a collection, in the same shape as the favourites
  /// query (systems joined, so `systemFolderName` is populated).
  static Future<List<DatabaseGameModel>> getGamesInCollection(
    String collectionId,
  ) => SqliteService.getGamesInCollection(collectionId);
}
