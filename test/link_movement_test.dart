import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kioju_link_manager/db.dart';
import 'package:kioju_link_manager/services/link_service.dart';
import 'package:kioju_link_manager/services/collection_service.dart';
import 'package:kioju_link_manager/services/sync_strategy.dart';

void main() {
  group('Link Movement Tests', () {
    late Database database;

    setUpAll(() async {
      // Initialize Flutter binding for tests
      TestWidgetsFlutterBinding.ensureInitialized();
      
      // Initialize FFI
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Create in-memory database for each test
      database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            // Create tables matching the app schema
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
              )
            ''');

            await db.execute('''
              CREATE TABLE collections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                remote_id TEXT,
                name TEXT NOT NULL UNIQUE,
                description TEXT,
                visibility TEXT DEFAULT 'public',
                link_count INTEGER DEFAULT 0,
                is_dirty INTEGER DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                last_synced_at TEXT
              )
            ''');

            await db.execute('''
              CREATE TABLE collection_tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                collection_id INTEGER NOT NULL,
                tag_name TEXT NOT NULL,
                FOREIGN KEY (collection_id) REFERENCES collections (id) ON DELETE CASCADE,
                UNIQUE(collection_id, tag_name)
              )
            ''');

            await db.execute('''
              CREATE TABLE config (
                key TEXT PRIMARY KEY,
                value TEXT
              )
            ''');
          },
        ),
      );
      
      // Override the database instance for testing
      AppDb.setTestInstance(database);
    });

    tearDown(() async {
      await database.close();
      AppDb.clearInstance();
    });

    test('should move single link to collection', () async {
      final linkService = LinkService.instance;
      final collectionService = CollectionService.instance;
      
      // Create a collection
      final collection = await collectionService.createCollection(
        name: 'Test Collection',
        description: 'Test collection for link movement',
      );
      
      // Create a link
      final linkResult = await linkService.createLink(
        url: 'https://example.com',
        title: 'Test Link',
      );
      expect(linkResult.success, isTrue);
      
      // Get the created link
      final db = await AppDb.instance();
      final links = await db.query('links', where: 'url = ?', whereArgs: ['https://example.com']);
      expect(links.length, 1);
      final linkId = links.first['id'] as int;
      
      // Move link to collection
      final moveResult = await linkService.moveLink(
        linkId: linkId,
        toCollection: collection.name,
      );
      
      expect(moveResult.success, isTrue);
      
      // Verify link was moved
      final updatedLinks = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
      expect(updatedLinks.length, 1);
      expect(updatedLinks.first['collection'], collection.name);
      expect(updatedLinks.first['is_dirty'], 1); // Should be marked dirty in manual sync mode
    });

    test('should move multiple links to collection in bulk', () async {
      final linkService = LinkService.instance;
      final collectionService = CollectionService.instance;
      
      // Create a collection
      final collection = await collectionService.createCollection(
        name: 'Bulk Test Collection',
        description: 'Test collection for bulk link movement',
      );
      
      // Create multiple links
      final linkIds = <int>[];
      for (int i = 0; i < 3; i++) {
        final linkResult = await linkService.createLink(
          url: 'https://example$i.com',
          title: 'Test Link $i',
        );
        expect(linkResult.success, isTrue);
        
        // Get the created link ID
        final db = await AppDb.instance();
        final links = await db.query('links', where: 'url = ?', whereArgs: ['https://example$i.com']);
        expect(links.length, 1);
        linkIds.add(links.first['id'] as int);
      }
      
      // Track progress
      var progressCalls = 0;
      var lastCompleted = 0;
      var lastTotal = 0;
      
      // Move links to collection in bulk
      final bulkResult = await linkService.moveLinksBulk(
        linkIds: linkIds,
        toCollection: collection.name,
        onProgress: (completed, total) {
          progressCalls++;
          lastCompleted = completed;
          lastTotal = total;
        },
      );
      
      expect(bulkResult.success, isTrue);
      expect(progressCalls, greaterThan(0)); // Progress should be called
      expect(lastCompleted, linkIds.length); // All links should be completed
      expect(lastTotal, linkIds.length);
      
      // Verify all links were moved
      final db = await AppDb.instance();
      for (final linkId in linkIds) {
        final updatedLinks = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
        expect(updatedLinks.length, 1);
        expect(updatedLinks.first['collection'], collection.name);
        expect(updatedLinks.first['is_dirty'], 1); // Should be marked dirty in manual sync mode
      }
    });

    test('should move links to uncategorized', () async {
      final linkService = LinkService.instance;
      final collectionService = CollectionService.instance;
      
      // Create a collection
      final collection = await collectionService.createCollection(
        name: 'Source Collection',
        description: 'Source collection for link movement',
      );
      
      // Create a link in the collection
      final linkResult = await linkService.createLink(
        url: 'https://example.com',
        title: 'Test Link',
        collection: collection.name,
      );
      expect(linkResult.success, isTrue);
      
      // Get the created link
      final db = await AppDb.instance();
      final links = await db.query('links', where: 'url = ?', whereArgs: ['https://example.com']);
      expect(links.length, 1);
      final linkId = links.first['id'] as int;
      
      // Verify link is in collection
      expect(links.first['collection'], collection.name);
      
      // Move link to uncategorized (null collection)
      final moveResult = await linkService.moveLink(
        linkId: linkId,
        toCollection: null,
      );
      
      expect(moveResult.success, isTrue);
      
      // Verify link was moved to uncategorized
      final updatedLinks = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
      expect(updatedLinks.length, 1);
      expect(updatedLinks.first['collection'], isNull);
      expect(updatedLinks.first['is_dirty'], 1); // Should be marked dirty in manual sync mode
    });

    test('should handle bulk move with partial failures gracefully', () async {
      final linkService = LinkService.instance;
      final collectionService = CollectionService.instance;
      
      // Create a collection
      final collection = await collectionService.createCollection(
        name: 'Target Collection',
        description: 'Target collection for bulk movement',
      );
      
      // Create one valid link
      final linkResult = await linkService.createLink(
        url: 'https://valid.com',
        title: 'Valid Link',
      );
      expect(linkResult.success, isTrue);
      
      // Get the created link ID
      final db = await AppDb.instance();
      final links = await db.query('links', where: 'url = ?', whereArgs: ['https://valid.com']);
      expect(links.length, 1);
      final validLinkId = links.first['id'] as int;
      
      // Try to move both valid and invalid link IDs
      final linkIds = [validLinkId, 99999]; // 99999 doesn't exist
      
      final bulkResult = await linkService.moveLinksBulk(
        linkIds: linkIds,
        toCollection: collection.name,
      );
      
      // Should handle partial failure gracefully
      expect(bulkResult.type, SyncResultType.immediatePartialFailure);
      expect(bulkResult.errorMessage, contains('errors'));
      
      // Valid link should still be moved
      final updatedLinks = await db.query('links', where: 'id = ?', whereArgs: [validLinkId]);
      expect(updatedLinks.length, 1);
      expect(updatedLinks.first['collection'], collection.name);
    });
  });
}
