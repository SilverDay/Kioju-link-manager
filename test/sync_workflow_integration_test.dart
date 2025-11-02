import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kioju_link_manager/db.dart';
import 'package:kioju_link_manager/services/sync_settings.dart';
import 'package:kioju_link_manager/services/sync_strategy_factory.dart';
import 'package:kioju_link_manager/services/link_service.dart';
import 'package:kioju_link_manager/services/collection_service.dart';

void main() {
  group('Sync Workflow Integration Tests', () {
    late Database database;

    setUpAll(() async {
      // Initialize Flutter binding for tests
      TestWidgetsFlutterBinding.ensureInitialized();

      // Initialize FFI
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      SyncSettings.clearCache();
      SyncStrategyFactory.clearCache();

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
      SyncSettings.clearCache();
      SyncStrategyFactory.clearCache();
    });

    group('Manual Sync Workflow', () {
      setUp(() async {
        // Set to manual sync mode
        await SyncSettings.setImmediateSyncEnabled(false);
      });

      test(
        'should mark links as dirty when created in manual sync mode',
        () async {
          final linkService = LinkService.instance;

          // Create a link
          final result = await linkService.createLink(
            url: 'https://example.com',
            title: 'Test Link',
          );

          expect(result.success, isTrue);
          expect(result.type.name, 'manualQueued');

          // Verify link is marked as dirty
          final links = await database.query(
            'links',
            where: 'url = ?',
            whereArgs: ['https://example.com'],
          );
          expect(links.length, 1);
          expect(links.first['is_dirty'], 1);
          expect(links.first['last_synced_at'], isNull);
        },
      );

      test(
        'should mark collections as dirty when created in manual sync mode',
        () async {
          final collectionService = CollectionService.instance;

          // Create a collection
          final collection = await collectionService.createCollection(
            name: 'Test Collection',
            description: 'Test description',
          );

          expect(collection.isDirty, isTrue);

          // Verify collection is marked as dirty in database
          final collections = await database.query(
            'collections',
            where: 'id = ?',
            whereArgs: [collection.id],
          );
          expect(collections.length, 1);
          expect(collections.first['is_dirty'], 1);
        },
      );

      test(
        'should mark links as dirty when moved in manual sync mode',
        () async {
          final linkService = LinkService.instance;
          final collectionService = CollectionService.instance;

          // Create a collection
          final collection = await collectionService.createCollection(
            name: 'Target Collection',
          );

          // Create a link
          final linkResult = await linkService.createLink(
            url: 'https://example.com',
            title: 'Test Link',
          );
          expect(linkResult.success, isTrue);

          // Get the created link ID
          final links = await database.query(
            'links',
            where: 'url = ?',
            whereArgs: ['https://example.com'],
          );
          final linkId = links.first['id'] as int;

          // Reset dirty flag to test movement
          await database.update(
            'links',
            {'is_dirty': 0},
            where: 'id = ?',
            whereArgs: [linkId],
          );

          // Move link to collection
          final moveResult = await linkService.moveLink(
            linkId: linkId,
            toCollection: collection.name,
          );

          expect(moveResult.success, isTrue);
          expect(moveResult.type.name, 'manualQueued');

          // Verify link is marked as dirty after move
          final updatedLinks = await database.query(
            'links',
            where: 'id = ?',
            whereArgs: [linkId],
          );
          expect(updatedLinks.first['is_dirty'], 1);
          expect(updatedLinks.first['collection'], collection.name);
        },
      );

      test('should handle bulk operations in manual sync mode', () async {
        final linkService = LinkService.instance;
        final collectionService = CollectionService.instance;

        // Create a collection
        final collection = await collectionService.createCollection(
          name: 'Bulk Target Collection',
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
          final links = await database.query(
            'links',
            where: 'url = ?',
            whereArgs: ['https://example$i.com'],
          );
          linkIds.add(links.first['id'] as int);

          // Reset dirty flag to test bulk movement
          await database.update(
            'links',
            {'is_dirty': 0},
            where: 'id = ?',
            whereArgs: [links.first['id']],
          );
        }

        // Move links in bulk
        final bulkResult = await linkService.moveLinksBulk(
          linkIds: linkIds,
          toCollection: collection.name,
        );

        expect(bulkResult.success, isTrue);
        expect(bulkResult.type.name, 'manualQueued');

        // Verify all links are marked as dirty
        for (final linkId in linkIds) {
          final links = await database.query(
            'links',
            where: 'id = ?',
            whereArgs: [linkId],
          );
          expect(links.first['is_dirty'], 1);
          expect(links.first['collection'], collection.name);
        }
      });
    });

    group('Immediate Sync Workflow', () {
      setUp(() async {
        // Set to immediate sync mode
        await SyncSettings.setImmediateSyncEnabled(true);
      });

      test('should attempt immediate sync when creating links', () async {
        final linkService = LinkService.instance;

        // Create a link - this will fail due to no API token, but should attempt immediate sync
        final result = await linkService.createLink(
          url: 'https://example.com',
          title: 'Test Link',
        );

        // Should fail due to no API token, but attempt immediate sync
        expect(result.success, isFalse);
        expect(result.type.name, 'immediateFailure');
        expect(result.errorMessage, contains('No API token configured'));

        // Link should still be created locally and marked as dirty (fallback behavior)
        final links = await database.query(
          'links',
          where: 'url = ?',
          whereArgs: ['https://example.com'],
        );
        expect(links.length, 1);
        expect(links.first['is_dirty'], 1); // Marked dirty due to sync failure
      });

      test('should attempt immediate sync when creating collections', () async {
        final collectionService = CollectionService.instance;

        // Create a collection - this will fail due to no API token, but should attempt immediate sync
        final collection = await collectionService.createCollection(
          name: 'Test Collection',
          description: 'Test description',
        );

        // Collection should be created locally and marked as dirty (fallback behavior)
        expect(collection.isDirty, isTrue);

        // Verify collection exists in database
        final collections = await database.query(
          'collections',
          where: 'id = ?',
          whereArgs: [collection.id],
        );
        expect(collections.length, 1);
        expect(collections.first['is_dirty'], 1);
      });

      test('should switch sync strategies when preference changes', () async {
        final linkService = LinkService.instance;

        // Create a link in immediate sync mode (will fail but attempt immediate sync)
        final result1 = await linkService.createLink(
          url: 'https://example1.com',
          title: 'Test Link 1',
        );
        expect(result1.type.name, 'immediateFailure');

        // Switch to manual sync mode
        await SyncSettings.setImmediateSyncEnabled(false);

        // Create another link in manual sync mode
        final result2 = await linkService.createLink(
          url: 'https://example2.com',
          title: 'Test Link 2',
        );
        expect(result2.type.name, 'manualQueued');

        // Both links should exist and be marked as dirty
        final links = await database.query('links', orderBy: 'id');
        expect(links.length, 2);
        expect(links[0]['is_dirty'], 1);
        expect(links[1]['is_dirty'], 1);
      });
    });

    group('Sync Preference Persistence', () {
      test('should persist sync preference across service restarts', () async {
        // Set immediate sync enabled
        await SyncSettings.setImmediateSyncEnabled(true);

        // Clear cache to simulate service restart
        SyncSettings.clearCache();
        SyncStrategyFactory.clearCache();

        // Verify preference is still enabled
        final isEnabled = await SyncSettings.isImmediateSyncEnabled();
        expect(isEnabled, isTrue);

        // Verify strategy factory returns correct strategy
        final strategy = await SyncStrategyFactory.getStrategy();
        expect(strategy.runtimeType.toString(), 'ImmediateSyncStrategy');
      });

      test('should handle sync preference changes during operations', () async {
        final linkService = LinkService.instance;

        // Start in manual sync mode
        await SyncSettings.setImmediateSyncEnabled(false);

        // Create a link
        final result1 = await linkService.createLink(
          url: 'https://example1.com',
          title: 'Test Link 1',
        );
        expect(result1.type.name, 'manualQueued');

        // Change to immediate sync mode
        await SyncSettings.setImmediateSyncEnabled(true);

        // Create another link - should use new strategy
        final result2 = await linkService.createLink(
          url: 'https://example2.com',
          title: 'Test Link 2',
        );
        expect(
          result2.type.name,
          'immediateFailure',
        ); // Fails due to no API token

        // Both links should exist
        final links = await database.query('links', orderBy: 'id');
        expect(links.length, 2);
      });
    });

    group('Error Handling in Sync Workflows', () {
      test('should handle sync errors gracefully in manual sync', () async {
        // Set to manual sync mode
        await SyncSettings.setImmediateSyncEnabled(false);

        final linkService = LinkService.instance;

        // Create a link - should succeed in manual sync mode even without API token
        final result = await linkService.createLink(
          url: 'https://example.com',
          title: 'Test Link',
        );

        // Should succeed in manual sync mode (queued for later sync)
        expect(result.success, isTrue);
        expect(result.type.name, 'manualQueued');
      });

      test('should fallback to manual sync when immediate sync fails', () async {
        // Set to immediate sync mode
        await SyncSettings.setImmediateSyncEnabled(true);

        final linkService = LinkService.instance;

        // Create a link - will fail due to no API token but should fallback
        final result = await linkService.createLink(
          url: 'https://example.com',
          title: 'Test Link',
        );

        expect(result.success, isFalse);
        expect(result.type.name, 'immediateFailure');

        // Link should still be created locally and marked dirty for later sync
        final links = await database.query(
          'links',
          where: 'url = ?',
          whereArgs: ['https://example.com'],
        );
        expect(links.length, 1);
        expect(links.first['is_dirty'], 1);
      });
    });
  });
}
