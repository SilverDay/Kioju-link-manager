import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kioju_link_manager/db.dart';
import 'package:kioju_link_manager/services/sync_strategy.dart';
import 'package:kioju_link_manager/services/sync_strategy_factory.dart';
import 'package:kioju_link_manager/services/immediate_sync_strategy.dart';
import 'package:kioju_link_manager/services/manual_sync_strategy.dart';
import 'package:kioju_link_manager/services/sync_settings.dart';
import 'package:kioju_link_manager/services/cancellation_token.dart';

void main() {
  group('Sync Strategy Tests', () {
    late Database database;

    setUpAll(() {
      // Initialize FFI for testing
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
                remote_id TEXT,
                url TEXT NOT NULL,
                title TEXT,
                notes TEXT,
                tags TEXT,
                collection TEXT,
                is_private INTEGER DEFAULT 0,
                is_dirty INTEGER DEFAULT 0,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                last_synced_at TEXT
              )
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

    group('SyncStrategyFactory', () {
      test(
        'should return ManualSyncStrategy when immediate sync is disabled',
        () async {
          // Set to manual sync mode
          await SyncSettings.setImmediateSyncEnabled(false);

          final strategy = await SyncStrategyFactory.getStrategy();
          expect(strategy, isA<ManualSyncStrategy>());
        },
      );

      test(
        'should return ImmediateSyncStrategy when immediate sync is enabled',
        () async {
          // Set to immediate sync mode
          await SyncSettings.setImmediateSyncEnabled(true);

          final strategy = await SyncStrategyFactory.getStrategy();
          expect(strategy, isA<ImmediateSyncStrategy>());
        },
      );

      test('should use singleton pattern for strategy instances', () async {
        // Set to manual sync mode
        await SyncSettings.setImmediateSyncEnabled(false);

        final strategy1 = await SyncStrategyFactory.getStrategy();
        final strategy2 = await SyncStrategyFactory.getStrategy();
        expect(identical(strategy1, strategy2), isTrue);

        // Switch to immediate sync mode
        await SyncSettings.setImmediateSyncEnabled(true);

        final strategy3 = await SyncStrategyFactory.getStrategy();
        final strategy4 = await SyncStrategyFactory.getStrategy();
        expect(identical(strategy3, strategy4), isTrue);

        // Different strategy types should not be identical
        expect(identical(strategy1, strategy3), isFalse);
      });

      test('should clear cached strategies', () async {
        // Get a strategy
        await SyncSettings.setImmediateSyncEnabled(false);
        final strategy1 = await SyncStrategyFactory.getStrategy();

        // Clear cache
        SyncStrategyFactory.clearCache();

        // Get strategy again - should be a new instance
        final strategy2 = await SyncStrategyFactory.getStrategy();
        expect(identical(strategy1, strategy2), isFalse);
      });
    });

    group('ManualSyncStrategy', () {
      late ManualSyncStrategy strategy;

      setUp(() {
        strategy = ManualSyncStrategy();
      });

      test('should return manualQueued result for link operations', () async {
        // Create a test link
        final linkId = await database.insert('links', {
          'url': 'https://example.com',
          'title': 'Test Link',
          'is_dirty': 0,
        });

        // Create a real link operation
        final operation = LinkCreateOperation(
          localId: linkId,
          url: 'https://example.com',
          title: 'Test Link',
          markAsSynced: (remoteId) async {},
        );

        final result = await strategy.executeSync(operation);

        expect(result.success, isTrue);
        expect(result.type, SyncResultType.manualQueued);
        expect(result.errorMessage, isNull);
      });

      test(
        'should mark link as dirty when processing link operation',
        () async {
          // Create a test link
          final linkId = await database.insert('links', {
            'url': 'https://example.com',
            'title': 'Test Link',
            'is_dirty': 0,
          });

          // Create a real link operation
          final operation = LinkCreateOperation(
            localId: linkId,
            url: 'https://example.com',
            title: 'Test Link',
            markAsSynced: (remoteId) async {},
          );

          await strategy.executeSync(operation);

          // Verify link is marked as dirty
          final links = await database.query(
            'links',
            where: 'id = ?',
            whereArgs: [linkId],
          );
          expect(links.length, 1);
          expect(links.first['is_dirty'], 1);
          expect(links.first['last_synced_at'], isNull);
        },
      );

      test(
        'should mark collection as dirty when processing collection operation',
        () async {
          // Create a test collection
          final collectionId = await database.insert('collections', {
            'name': 'Test Collection',
            'is_dirty': 0,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

          // Create a real collection operation
          final operation = CollectionCreateOperation(
            localId: collectionId,
            name: 'Test Collection',
            visibility: 'public',
            markAsSynced: (remoteId) async {},
          );

          await strategy.executeSync(operation);

          // Verify collection is marked as dirty
          final collections = await database.query(
            'collections',
            where: 'id = ?',
            whereArgs: [collectionId],
          );
          expect(collections.length, 1);
          expect(collections.first['is_dirty'], 1);
          expect(collections.first['last_synced_at'], isNull);
        },
      );

      test('should handle bulk operations with progress tracking', () async {
        // Create test links
        final linkIds = <int>[];
        for (int i = 0; i < 3; i++) {
          final linkId = await database.insert('links', {
            'url': 'https://example$i.com',
            'title': 'Test Link $i',
            'is_dirty': 0,
          });
          linkIds.add(linkId);
        }

        // Track progress
        var progressCalls = 0;
        var lastCompleted = 0;
        var lastTotal = 0;

        // Create bulk operation
        final subOperations =
            linkIds
                .map(
                  (id) => LinkCreateOperation(
                    localId: id,
                    url: 'https://example$id.com',
                    title: 'Test Link $id',
                    markAsSynced: (remoteId) async {},
                  ),
                )
                .toList();
        final bulkOperation = BulkOperation(
          operations: subOperations,
          onProgress: (completed, total) {
            progressCalls++;
            lastCompleted = completed;
            lastTotal = total;
          },
        );

        final result = await strategy.executeSync(bulkOperation);

        expect(result.success, isTrue);
        expect(result.type, SyncResultType.manualQueued);
        expect(progressCalls, greaterThan(0));
        expect(lastCompleted, linkIds.length);
        expect(lastTotal, linkIds.length);

        // Verify all links are marked as dirty
        for (final linkId in linkIds) {
          final links = await database.query(
            'links',
            where: 'id = ?',
            whereArgs: [linkId],
          );
          expect(links.length, 1);
          expect(links.first['is_dirty'], 1);
        }
      });
    });

    group('ImmediateSyncStrategy', () {
      late ImmediateSyncStrategy strategy;

      setUp(() {
        strategy = ImmediateSyncStrategy();
      });

      test('should return failure when no API token is configured', () async {
        // Ensure no token is set (this is the default in test environment)

        final operation = LinkCreateOperation(
          localId: 1,
          url: 'https://example.com',
          title: 'Test Link',
          markAsSynced: (remoteId) async {},
        );

        final result = await strategy.executeSync(operation);

        expect(result.success, isFalse);
        expect(result.type, SyncResultType.immediateFailure);
        expect(result.errorMessage, contains('No API token configured'));
      });

      test('should handle cancellation properly', () async {
        final operation = LinkCreateOperation(
          localId: 1,
          url: 'https://example.com',
          title: 'Test Link',
          markAsSynced: (remoteId) async {},
        );

        // Create a cancelled token
        final cancelledToken = CancellationToken.cancelled('Test cancellation');
        strategy.setCancellationToken(cancelledToken);

        final result = await strategy.executeSync(operation);

        expect(result.success, isFalse);
        expect(result.type, SyncResultType.immediateFailure);
        expect(result.errorMessage, contains('cancelled'));
      });
    });

    group('SyncResult', () {
      test('should create immediate success result', () {
        final result = SyncResult.immediateSuccess();

        expect(result.success, isTrue);
        expect(result.type, SyncResultType.immediateSuccess);
        expect(result.errorMessage, isNull);
        expect(result.failedItemIds, isEmpty);
      });

      test('should create immediate failure result', () {
        final result = SyncResult.immediateFailure('Test error', [
          'item1',
          'item2',
        ]);

        expect(result.success, isFalse);
        expect(result.type, SyncResultType.immediateFailure);
        expect(result.errorMessage, 'Test error');
        expect(result.failedItemIds, ['item1', 'item2']);
      });

      test('should create immediate partial failure result', () {
        final result = SyncResult.immediatePartialFailure('Partial error', [
          'item1',
        ]);

        expect(result.success, isFalse);
        expect(result.type, SyncResultType.immediatePartialFailure);
        expect(result.errorMessage, 'Partial error');
        expect(result.failedItemIds, ['item1']);
      });

      test('should create manual queued result', () {
        final result = SyncResult.manualQueued();

        expect(result.success, isTrue);
        expect(result.type, SyncResultType.manualQueued);
        expect(result.errorMessage, isNull);
        expect(result.failedItemIds, isEmpty);
      });
    });
  });
}
