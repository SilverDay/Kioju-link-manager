import 'sync_strategy.dart';
import 'cancellation_token.dart';
import '../db.dart';
import 'immediate_sync_strategy.dart'
    show
        BulkOperation,
        ImportOperation,
        CollectionCreateOperation,
        CollectionUpdateOperation,
        CollectionDeleteOperation,
        LinkCreateOperation,
        LinkUpdateOperation,
        LinkDeleteOperation,
        LinkMoveOperation;

/// Sync strategy that marks items as dirty for later manual sync
class ManualSyncStrategy with CancellationSupport implements SyncStrategy {
  @override
  Future<SyncResult> executeSync(SyncOperation operation) async {
    try {
      // Check for cancellation before starting
      checkCancellation();

      // Mark the item as dirty for later sync
      await _markAsDirty(operation);

      return SyncResult.manualQueued();
    } catch (e) {
      // Handle cancellation specifically
      if (e is OperationCancelledException) {
        return SyncResult.immediateFailure(
          'Operation cancelled: ${e.message}',
          [operation.operationId],
        );
      }

      // Even manual sync can fail if database operations fail
      return SyncResult.immediateFailure(
        'Failed to mark item for sync: ${e.toString()}',
        [operation.operationId],
      );
    }
  }

  /// Marks the appropriate items as dirty based on the operation type
  Future<void> _markAsDirty(SyncOperation operation) async {
    checkCancellation();

    final db = await AppDb.instance();

    switch (operation.runtimeType.toString()) {
      case 'LinkCreateOperation':
      case 'LinkUpdateOperation':
      case 'LinkDeleteOperation':
      case 'LinkMoveOperation':
        await _markLinkAsDirty(db, operation);
        break;
      case 'CollectionCreateOperation':
      case 'CollectionUpdateOperation':
      case 'CollectionDeleteOperation':
        await _markCollectionAsDirty(db, operation);
        break;
      case 'BulkOperation':
        await _markBulkOperationAsDirty(db, operation as BulkOperation);
        break;
      case 'ImportOperation':
        await _markImportOperationAsDirty(db, operation as ImportOperation);
        break;
      default:
        throw Exception(
          'Unknown sync operation type: ${operation.runtimeType}',
        );
    }
  }

  Future<void> _markLinkAsDirty(dynamic db, SyncOperation operation) async {
    int? linkId;

    if (operation is LinkCreateOperation) {
      linkId = operation.localId;
    } else if (operation is LinkUpdateOperation) {
      linkId = operation.localId;
    } else if (operation is LinkDeleteOperation) {
      linkId = operation.localId;
    } else if (operation is LinkMoveOperation) {
      linkId = operation.localId;
    }

    if (linkId != null) {
      await db.update(
        'links',
        {
          'is_dirty': 1,
          'last_synced_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [linkId],
      );
    }
  }

  Future<void> _markCollectionAsDirty(
    dynamic db,
    SyncOperation operation,
  ) async {
    int? collectionId;

    if (operation is CollectionCreateOperation) {
      collectionId = operation.localId;
    } else if (operation is CollectionUpdateOperation) {
      collectionId = operation.localId;
    } else if (operation is CollectionDeleteOperation) {
      collectionId = operation.localId;
    }

    if (collectionId != null) {
      await db.update(
        'collections',
        {
          'is_dirty': 1,
          'last_synced_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [collectionId],
      );
    }
  }

  Future<void> _markBulkOperationAsDirty(
    dynamic db,
    BulkOperation operation,
  ) async {
    // Process each sub-operation to mark items as dirty
    int completed = 0;
    for (final subOperation in operation.operations) {
      checkCancellation(); // Check for cancellation before each sub-operation
      await _markAsDirty(subOperation);
      completed++;
      operation.onProgress?.call(completed, operation.operations.length);
    }
  }

  Future<void> _markImportOperationAsDirty(
    dynamic db,
    ImportOperation operation,
  ) async {
    // Mark all imported links as dirty for later sync
    int completed = 0;
    for (final linkData in operation.importedLinks) {
      checkCancellation(); // Check for cancellation before each link

      if (linkData['localId'] != null) {
        await db.update(
          'links',
          {
            'is_dirty': 1,
            'last_synced_at': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkData['localId']],
        );
      }
      completed++;
      operation.onProgress?.call(completed, operation.importedLinks.length);
    }
  }
}
