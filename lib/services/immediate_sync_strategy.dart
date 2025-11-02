import 'sync_strategy.dart';
import 'kioju_api.dart';
import 'sync_retry_service.dart';
import 'cancellation_token.dart';
import '../db.dart';

/// Sync strategy that immediately syncs changes to the server
class ImmediateSyncStrategy with CancellationSupport implements SyncStrategy {
  @override
  Future<SyncResult> executeSync(SyncOperation operation) async {
    try {
      // Check for cancellation before starting
      checkCancellation();

      // Check if we have a valid API token
      if (!await KiojuApi.hasToken()) {
        return SyncResult.immediateFailure(
          'No API token configured. Please set up your API token in settings.',
        );
      }

      // Execute the specific sync operation with retry logic
      await SyncRetryService.executeWithRetry(
        () => executeWithCancellation(() => _executeSyncOperation(operation)),
        shouldRetry: (error) {
          // Don't retry if cancelled
          if (error is OperationCancelledException) {
            return false;
          }
          return SyncRetryService.shouldRetryError(error);
        },
      );

      return SyncResult.immediateSuccess();
    } catch (e) {
      // Handle cancellation specifically
      if (e is OperationCancelledException) {
        return SyncResult.immediateFailure('Sync cancelled: ${e.message}', [
          operation.operationId,
        ]);
      }

      // Return failure result - caller will handle marking as dirty
      return SyncResult.immediateFailure('Sync failed: ${e.toString()}', [
        operation.operationId,
      ]);
    }
  }

  /// Executes the specific sync operation based on its type
  Future<void> _executeSyncOperation(SyncOperation operation) async {
    // Check for cancellation before each operation
    checkCancellation();

    switch (operation.runtimeType.toString()) {
      case 'LinkCreateOperation':
        await _syncLinkCreate(operation as LinkCreateOperation);
        break;
      case 'LinkUpdateOperation':
        await _syncLinkUpdate(operation as LinkUpdateOperation);
        break;
      case 'LinkDeleteOperation':
        await _syncLinkDelete(operation as LinkDeleteOperation);
        break;
      case 'LinkMoveOperation':
        await _syncLinkMove(operation as LinkMoveOperation);
        break;
      case 'CollectionCreateOperation':
        await _syncCollectionCreate(operation as CollectionCreateOperation);
        break;
      case 'CollectionUpdateOperation':
        await _syncCollectionUpdate(operation as CollectionUpdateOperation);
        break;
      case 'CollectionDeleteOperation':
        await _syncCollectionDelete(operation as CollectionDeleteOperation);
        break;
      case 'BulkOperation':
        await _syncBulkOperation(operation as BulkOperation);
        break;
      case 'ImportOperation':
        await _syncImportOperation(operation as ImportOperation);
        break;
      default:
        throw Exception(
          'Unknown sync operation type: ${operation.runtimeType}',
        );
    }
  }

  Future<void> _syncLinkCreate(LinkCreateOperation operation) async {
    checkCancellation();

    final response = await KiojuApi.addLink(
      url: operation.url,
      title: operation.title,
      tags: operation.tags,
      isPrivate: operation.isPrivate ? '1' : '0',
    );

    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to create link on server');
    }

    // Update local link with remote ID
    final remoteId = response['id']?.toString();
    if (remoteId != null) {
      await operation.markAsSynced(remoteId);
    }

    // If link was created with a collection, assign it after creation
    if (operation.collection != null && remoteId != null) {
      try {
        // Get collection remote ID
        final db = await AppDb.instance();
        final collectionRows = await db.query(
          'collections',
          where: 'name = ?',
          whereArgs: [operation.collection],
        );

        if (collectionRows.isNotEmpty) {
          final collectionRemoteId =
              collectionRows.first['remote_id'] as String?;
          if (collectionRemoteId != null) {
            await KiojuApi.assignLinkToCollection(
              linkId: remoteId,
              collectionId: collectionRemoteId,
            );
          }
        }
      } catch (e) {
        // Collection assignment failed, but link was created successfully
        // This is not a critical failure
      }
    }
  }

  Future<void> _syncLinkUpdate(LinkUpdateOperation operation) async {
    if (operation.remoteId == null) {
      throw Exception('Cannot update link: no remote ID');
    }

    final response = await KiojuApi.updateLink(
      id: operation.remoteId!,
      title: operation.title,
      description: operation.description,
      tags: operation.tags,
      isPrivate: operation.isPrivate ? '1' : '0',
    );

    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to update link on server');
    }

    // Mark as synced
    await operation.markAsSynced();
  }

  Future<void> _syncLinkDelete(LinkDeleteOperation operation) async {
    if (operation.remoteId == null) {
      // Link doesn't exist on server, nothing to delete
      return;
    }

    final response = await KiojuApi.deleteLink(operation.remoteId!);

    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to delete link on server');
    }
  }

  Future<void> _syncLinkMove(LinkMoveOperation operation) async {
    if (operation.remoteId == null) {
      throw Exception('Cannot move link: no remote ID');
    }

    // Get collection remote ID if moving to a collection
    String? collectionRemoteId;
    if (operation.toCollection != null) {
      final db = await AppDb.instance();
      final collectionRows = await db.query(
        'collections',
        where: 'name = ?',
        whereArgs: [operation.toCollection],
      );

      if (collectionRows.isNotEmpty) {
        collectionRemoteId = collectionRows.first['remote_id'] as String?;
      }

      if (collectionRemoteId == null) {
        throw Exception(
          'Cannot move link: target collection not found or not synced',
        );
      }
    }

    // Use the collection assignment API to move the link
    final response = await KiojuApi.assignLinkToCollection(
      linkId: operation.remoteId!,
      collectionId: collectionRemoteId,
    );

    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to move link on server');
    }

    // Mark as synced
    await operation.markAsSynced();
  }

  Future<void> _syncCollectionCreate(
    CollectionCreateOperation operation,
  ) async {
    final response = await KiojuApi.createCollection(
      name: operation.name,
      description: operation.description,
      visibility: operation.visibility,
      tags: operation.tags,
    );

    if (response['success'] != true) {
      throw Exception(
        response['message'] ?? 'Failed to create collection on server',
      );
    }

    // Update local collection with remote ID
    final apiCollection = response['collection'];
    final remoteId = apiCollection['id']?.toString();

    if (remoteId != null && operation.localId != null) {
      await operation.markAsSynced(remoteId);
    }
  }

  Future<void> _syncCollectionUpdate(
    CollectionUpdateOperation operation,
  ) async {
    if (operation.remoteId == null) {
      throw Exception('Cannot update collection: no remote ID');
    }

    final response = await KiojuApi.updateCollection(
      id: operation.remoteId!,
      name: operation.name,
      description: operation.description,
      visibility: operation.visibility,
      tags: operation.tags,
    );

    if (response['success'] != true) {
      throw Exception(
        response['message'] ?? 'Failed to update collection on server',
      );
    }

    // Mark as synced
    if (operation.localId != null) {
      await operation.markAsSynced(operation.remoteId!);
    }
  }

  Future<void> _syncCollectionDelete(
    CollectionDeleteOperation operation,
  ) async {
    if (operation.remoteId == null) {
      // Collection doesn't exist on server, nothing to delete
      return;
    }

    final response = await KiojuApi.deleteCollection(id: operation.remoteId!);

    if (response['success'] != true) {
      throw Exception(
        response['message'] ?? 'Failed to delete collection on server',
      );
    }
  }

  Future<void> _syncBulkOperation(BulkOperation operation) async {
    final errors = <String>[];
    int completed = 0;

    for (final subOperation in operation.operations) {
      try {
        checkCancellation(); // Check for cancellation before each sub-operation
        await _executeSyncOperation(subOperation);
        completed++;
        operation.onProgress?.call(completed, operation.operations.length);
      } catch (e) {
        if (e is OperationCancelledException) {
          // If cancelled, stop processing remaining operations
          rethrow;
        }
        errors.add(
          '${subOperation.operationType} (${subOperation.operationId}): ${e.toString()}',
        );
        // Continue with other operations even if one fails
      }
    }

    if (errors.isNotEmpty) {
      // For bulk operations, we want to provide detailed error information
      // but still indicate partial success if some operations succeeded
      if (completed > 0) {
        throw Exception(
          'Bulk operation partially completed: $completed/${operation.operations.length} succeeded. Errors: ${errors.join('; ')}',
        );
      } else {
        throw Exception(
          'Bulk operation failed completely. Errors: ${errors.join('; ')}',
        );
      }
    }
  }

  Future<void> _syncImportOperation(ImportOperation operation) async {
    final errors = <String>[];
    int completed = 0;

    // Process each imported link
    for (final linkData in operation.importedLinks) {
      try {
        checkCancellation(); // Check for cancellation before each link

        // Create link on server
        final response = await KiojuApi.addLink(
          url: linkData['url'] as String,
          title: linkData['title'] as String?,
          tags: (linkData['tags'] as List<String>?) ?? [],
          isPrivate: '1', // Default to private for imported links
        );

        if (response['success'] != true) {
          throw Exception(
            response['message'] ?? 'Failed to create link on server',
          );
        }

        // Update local link with remote ID
        final remoteId = response['id']?.toString();
        if (remoteId != null && linkData['localId'] != null) {
          final db = await AppDb.instance();
          await db.update(
            'links',
            {
              'remote_id': remoteId,
              'is_dirty': 0,
              'last_synced_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [linkData['localId']],
          );

          // If link has a collection, assign it after creation
          if (linkData['collection'] != null) {
            try {
              // Get collection remote ID
              final collectionRows = await db.query(
                'collections',
                where: 'name = ?',
                whereArgs: [linkData['collection']],
              );

              if (collectionRows.isNotEmpty) {
                final collectionRemoteId =
                    collectionRows.first['remote_id'] as String?;
                if (collectionRemoteId != null) {
                  await KiojuApi.assignLinkToCollection(
                    linkId: remoteId,
                    collectionId: collectionRemoteId,
                  );
                }
              }
            } catch (e) {
              // Collection assignment failed, but link was created successfully
              // This is not a critical failure
            }
          }
        }

        completed++;
        operation.onProgress?.call(completed, operation.importedLinks.length);
      } catch (e) {
        errors.add('Link ${linkData['url']}: ${e.toString()}');

        // Mark as dirty for later sync if immediate sync fails
        if (linkData['localId'] != null) {
          try {
            final db = await AppDb.instance();
            await db.update(
              'links',
              {'is_dirty': 1, 'last_synced_at': null},
              where: 'id = ?',
              whereArgs: [linkData['localId']],
            );
          } catch (_) {
            // Ignore database update errors
          }
        }
      }
    }

    if (errors.isNotEmpty) {
      // For import operations, we want to provide detailed error information
      // but still indicate partial success if some operations succeeded
      if (completed > 0) {
        throw Exception(
          'Import partially completed: $completed/${operation.importedLinks.length} links synced. Errors: ${errors.join('; ')}',
        );
      } else {
        throw Exception(
          'Import sync failed completely. Errors: ${errors.join('; ')}',
        );
      }
    }
  }
}

// Link operation classes
class LinkCreateOperation extends SyncOperation {
  final int? localId;
  final String url;
  final String? title;
  final String? description;
  final List<String> tags;
  final bool isPrivate;
  final String? collection;
  final Function(String remoteId) markAsSynced;

  LinkCreateOperation({
    this.localId,
    required this.url,
    this.title,
    this.description,
    this.tags = const [],
    this.isPrivate = true,
    this.collection,
    required this.markAsSynced,
  });

  @override
  String get operationId => 'link_create_${localId ?? url.hashCode}';

  @override
  String get operationType => 'LinkCreate';
}

class LinkUpdateOperation extends SyncOperation {
  final int localId;
  final String? remoteId;
  final String url;
  final String? title;
  final String? description;
  final List<String> tags;
  final bool isPrivate;
  final String? collection;
  final Function() markAsSynced;

  LinkUpdateOperation({
    required this.localId,
    this.remoteId,
    required this.url,
    this.title,
    this.description,
    this.tags = const [],
    this.isPrivate = true,
    this.collection,
    required this.markAsSynced,
  });

  @override
  String get operationId => 'link_update_$localId';

  @override
  String get operationType => 'LinkUpdate';
}

class LinkDeleteOperation extends SyncOperation {
  final int localId;
  final String? remoteId;
  final String url;

  LinkDeleteOperation({
    required this.localId,
    this.remoteId,
    required this.url,
  });

  @override
  String get operationId => 'link_delete_$localId';

  @override
  String get operationType => 'LinkDelete';
}

class LinkMoveOperation extends SyncOperation {
  final int localId;
  final String? remoteId;
  final String url;
  final String? fromCollection;
  final String? toCollection;
  final Function() markAsSynced;

  LinkMoveOperation({
    required this.localId,
    this.remoteId,
    required this.url,
    this.fromCollection,
    this.toCollection,
    required this.markAsSynced,
  });

  @override
  String get operationId => 'link_move_$localId';

  @override
  String get operationType => 'LinkMove';
}

class CollectionCreateOperation extends SyncOperation {
  final String name;
  final String? description;
  final String visibility;
  final List<String> tags;
  final int? localId;
  final Function(String remoteId) markAsSynced;

  CollectionCreateOperation({
    required this.name,
    this.description,
    required this.visibility,
    this.tags = const [],
    this.localId,
    required this.markAsSynced,
  });

  @override
  String get operationId => 'collection_create_${localId ?? name}';

  @override
  String get operationType => 'CollectionCreate';
}

class CollectionUpdateOperation extends SyncOperation {
  final int? localId;
  final String? remoteId;
  final String name;
  final String? description;
  final String visibility;
  final List<String> tags;
  final Function(String remoteId) markAsSynced;

  CollectionUpdateOperation({
    this.localId,
    this.remoteId,
    required this.name,
    this.description,
    required this.visibility,
    this.tags = const [],
    required this.markAsSynced,
  });

  @override
  String get operationId => 'collection_update_${localId ?? remoteId}';

  @override
  String get operationType => 'CollectionUpdate';
}

class CollectionDeleteOperation extends SyncOperation {
  final int? localId;
  final String? remoteId;
  final String name;

  CollectionDeleteOperation({this.localId, this.remoteId, required this.name});

  @override
  String get operationId => 'collection_delete_${localId ?? remoteId}';

  @override
  String get operationType => 'CollectionDelete';
}

class BulkOperation extends SyncOperation {
  final List<SyncOperation> operations;
  final Function(int completed, int total)? onProgress;

  BulkOperation({required this.operations, this.onProgress});

  @override
  String get operationId => 'bulk_operation_${operations.length}_items';

  @override
  String get operationType => 'BulkOperation';
}

class ImportOperation extends SyncOperation {
  final List<Map<String, dynamic>> importedLinks;
  final Function(int completed, int total)? onProgress;

  ImportOperation({required this.importedLinks, this.onProgress});

  @override
  String get operationId => 'import_operation_${importedLinks.length}_links';

  @override
  String get operationType => 'ImportOperation';
}
