import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class AppDb {
  static sqflite.Database? _db;

  static Future<sqflite.Database> instance() async {
    if (_db != null) return _db!;

    // Use FFI on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'kioju', 'kioju_links.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);

    _db = await sqflite.openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
      CREATE TABLE links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT,
        notes TEXT,
        tags TEXT,
        collection TEXT,
        is_private INTEGER DEFAULT 0,
        is_dirty INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_synced_at TEXT,
        remote_id TEXT
      );
      ''');
        await db.execute('''
      CREATE TABLE config (
        key TEXT PRIMARY KEY,
        value TEXT
      );
      ''');
        await db.execute('''
      CREATE TABLE collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        visibility TEXT DEFAULT 'public',
        link_count INTEGER DEFAULT 0,
        is_dirty INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_synced_at TEXT
      );
      ''');
        await db.execute('''
      CREATE TABLE collection_tags (
        collection_id INTEGER,
        tag_name TEXT,
        FOREIGN KEY (collection_id) REFERENCES collections (id) ON DELETE CASCADE,
        PRIMARY KEY (collection_id, tag_name)
      );
      ''');
        await db.insert('config', {
          'key': 'base_url',
          'value': 'https://kioju.de/api/api.php',
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add is_private column for existing databases
          await db.execute(
            'ALTER TABLE links ADD COLUMN is_private INTEGER DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          // Add dirty flags and sync tracking to links table
          await db.execute(
            'ALTER TABLE links ADD COLUMN is_dirty INTEGER DEFAULT 0',
          );
          await db.execute('ALTER TABLE links ADD COLUMN last_synced_at TEXT');

          // Create collections table
          await db.execute('''
          CREATE TABLE collections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id TEXT UNIQUE,
            name TEXT NOT NULL,
            description TEXT,
            visibility TEXT DEFAULT 'public',
            link_count INTEGER DEFAULT 0,
            is_dirty INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            last_synced_at TEXT
          );
          ''');

          // Create collection tags junction table
          await db.execute('''
          CREATE TABLE collection_tags (
            collection_id INTEGER,
            tag_name TEXT,
            FOREIGN KEY (collection_id) REFERENCES collections (id) ON DELETE CASCADE,
            PRIMARY KEY (collection_id, tag_name)
          );
          ''');
        }
      },
    );

    return _db!;
  }

  /// Get database version for migration tracking
  static Future<int> getDatabaseVersion() async {
    final db = await instance();
    return await db.getVersion();
  }

  /// Check if collections table exists (for migration validation)
  static Future<bool> collectionsTableExists() async {
    final db = await instance();
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='collections'",
    );
    return result.isNotEmpty;
  }

  /// Update link count for a collection
  static Future<void> updateCollectionLinkCount(int collectionId) async {
    final db = await instance();

    // Count links in this collection
    final countResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM links 
      WHERE collection = (
        SELECT name FROM collections WHERE id = ?
      )
    ''',
      [collectionId],
    );

    final count = countResult.first['count'] as int;

    // Update collection link count
    await db.update(
      'collections',
      {'link_count': count, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  /// Update all collection link counts
  static Future<void> updateAllCollectionLinkCounts() async {
    final db = await instance();

    // Get all collections
    final collections = await db.query('collections');

    for (final collection in collections) {
      final collectionId = collection['id'] as int;
      await updateCollectionLinkCount(collectionId);
    }
  }

  /// Mark collection as dirty for sync
  static Future<void> markCollectionDirty(int collectionId) async {
    final db = await instance();
    await db.update(
      'collections',
      {'is_dirty': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  /// Mark link as dirty for sync
  static Future<void> markLinkDirty(int linkId) async {
    final db = await instance();
    await db.update(
      'links',
      {'is_dirty': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [linkId],
    );
  }

  /// Get collections that need sync (dirty or never synced)
  static Future<List<Map<String, Object?>>> getCollectionsNeedingSync() async {
    final db = await instance();
    return await db.query(
      'collections',
      where: 'is_dirty = 1 OR last_synced_at IS NULL',
      orderBy: 'updated_at DESC',
    );
  }

  /// Get links that need sync (dirty or never synced)
  static Future<List<Map<String, Object?>>> getLinksNeedingSync() async {
    final db = await instance();
    return await db.query(
      'links',
      where: 'is_dirty = 1 OR last_synced_at IS NULL',
      orderBy: 'updated_at DESC',
    );
  }

  /// Clear all dirty flags (after successful sync)
  static Future<void> clearAllDirtyFlags() async {
    final db = await instance();
    final now = DateTime.now().toIso8601String();

    await db.update('collections', {
      'is_dirty': 0,
      'last_synced_at': now,
    }, where: 'is_dirty = 1');

    await db.update('links', {
      'is_dirty': 0,
      'last_synced_at': now,
    }, where: 'is_dirty = 1');
  }

  // Test support method
  static void setTestInstance(sqflite.Database testDb) {
    _db = testDb;
  }

  static void clearInstance() {
    _db = null;
  }
}
