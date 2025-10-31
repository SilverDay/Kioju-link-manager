import '../db.dart';
import '../models/link.dart';
import 'sync_settings.dart';
import 'sync_strategy.dart';
import 'sync_strategy_factory.dart';
import 'background_sync_executor.dart';
import 'cancellation_token.dart';
import 'immediate_sync_strategy.dart';
import 'manual_sync_strategy.dart';

/// Service for managing link operations with configurable sync behavior
class LinkService {
  static final LinkService _instance = LinkService._internal();
  static LinkService get instance => _instance;
  LinkService._internal();

  /// Creates a new link with configurable sync behavior
  Future<SyncResult> createLink({
    required String url,
    String? title,
    String? description,
    List<String> tags = const [],
    bool isPrivate = true,
    String? collection,
  }) async {
    final db = await AppDb.instance();
    
    // Insert link into local database first
    final linkId = await db.insert('links', {
      'url': url,
      'title': title,
      'notes': description,
      'tags': tags.join(','),
      'is_private': isPrivate ? 1 : 0,
      'collection': collection,
      'is_dirty': 1, // Always mark as dirty initially
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Create sync operation
    final operation = LinkCreateOperation(
      localId: linkId,
      url: url,
      title: title,
      description: description,
      tags: tags,
      isPrivate: isPrivate,
      collection: collection,
      markAsSynced: (remoteId) async {
        await db.update(
          'links',
          {
            'remote_id': remoteId,
            'is_dirty': 0,
            'last_synced_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkId],
        );
      },
    );

    // Execute sync based on user preference
    final strategy = await _getSyncStrategy();
    final result = await strategy.executeSync(operation);

    // If immediate sync failed, mark as dirty for later sync
    if (!result.success && result.type == SyncResultType.immediateFailure) {
      await db.update(
        'links',
        {'is_dirty': 1, 'last_synced_at': null},
        where: 'id = ?',
        whereArgs: [linkId],
      );
    }

    return result;
  }

  /// Updates an existing link with configurable sync behavior
  Future<SyncResult> updateLink({
    required int linkId,
    String? title,
    String? description,
    List<String> tags = const [],
    bool isPrivate = true,
    String? collection,
  }) async {
    final db = await AppDb.instance();
    
    // Get current link data
    final linkRows = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
    if (linkRows.isEmpty) {
      return SyncResult.immediateFailure('Link not found');
    }
    
    final currentLink = LinkItem.fromMap(linkRows.first);
    
    // Update link in local database
    await db.update(
      'links',
      {
        'title': title,
        'notes': description,
        'tags': tags.join(','),
        'is_private': isPrivate ? 1 : 0,
        'collection': collection,
        'is_dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [linkId],
    );

    // Create sync operation
    final operation = LinkUpdateOperation(
      localId: linkId,
      remoteId: currentLink.remoteId,
      url: currentLink.url,
      title: title,
      description: description,
      tags: tags,
      isPrivate: isPrivate,
      collection: collection,
      markAsSynced: () async {
        await db.update(
          'links',
          {
            'is_dirty': 0,
            'last_synced_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkId],
        );
      },
    );

    // Execute sync based on user preference
    final strategy = await _getSyncStrategy();
    final result = await strategy.executeSync(operation);

    // If immediate sync failed, ensure it stays marked as dirty
    if (!result.success && result.type == SyncResultType.immediateFailure) {
      await db.update(
        'links',
        {'is_dirty': 1, 'last_synced_at': null},
        where: 'id = ?',
        whereArgs: [linkId],
      );
    }

    return result;
  }

  /// Deletes a link with configurable sync behavior
  Future<SyncResult> deleteLink({
    required int linkId,
  }) async {
    final db = await AppDb.instance();
    
    // Get current link data before deletion
    final linkRows = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
    if (linkRows.isEmpty) {
      return SyncResult.immediateFailure('Link not found');
    }
    
    final currentLink = LinkItem.fromMap(linkRows.first);
    
    // Create sync operation before deleting locally
    final operation = LinkDeleteOperation(
      localId: linkId,
      remoteId: currentLink.remoteId,
      url: currentLink.url,
    );

    // Execute sync based on user preference
    final strategy = await _getSyncStrategy();
    final result = await strategy.executeSync(operation);

    // Always delete locally regardless of sync result
    await db.delete('links', where: 'id = ?', whereArgs: [linkId]);

    return result;
  }

  /// Moves a link to a different collection with configurable sync behavior
  Future<SyncResult> moveLink({
    required int linkId,
    String? toCollection,
  }) async {
    final db = await AppDb.instance();
    
    // Get current link data
    final linkRows = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
    if (linkRows.isEmpty) {
      return SyncResult.immediateFailure('Link not found');
    }
    
    final currentLink = LinkItem.fromMap(linkRows.first);
    
    // Update link collection in local database
    await db.update(
      'links',
      {
        'collection': toCollection,
        'is_dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [linkId],
    );

    // Create sync operation
    final operation = LinkMoveOperation(
      localId: linkId,
      remoteId: currentLink.remoteId,
      url: currentLink.url,
      fromCollection: currentLink.collection,
      toCollection: toCollection,
      markAsSynced: () async {
        await db.update(
          'links',
          {
            'is_dirty': 0,
            'last_synced_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkId],
        );
      },
    );

    // Execute sync based on user preference
    final strategy = await _getSyncStrategy();
    final result = await strategy.executeSync(operation);

    // If immediate sync failed, ensure it stays marked as dirty
    if (!result.success && result.type == SyncResultType.immediateFailure) {
      await db.update(
        'links',
        {'is_dirty': 1, 'last_synced_at': null},
        where: 'id = ?',
        whereArgs: [linkId],
      );
    }

    return result;
  }

  /// Gets the appropriate sync strategy based on user preference
  Future<SyncStrategy> _getSyncStrategy() async {
    final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
    return isImmediateSync ? ImmediateSyncStrategy() : ManualSyncStrategy();
  }

  /// Moves multiple links to a collection with configurable sync behavior and progress tracking
  Future<SyncResult> moveLinksBulk({
    required List<int> linkIds,
    String? toCollection,
    Function(int completed, int total)? onProgress,
  }) async {
    final db = await AppDb.instance();
    final operations = <LinkMoveOperation>[];
    final errors = <String>[];
    
    // Prepare all operations
    for (int i = 0; i < linkIds.length; i++) {
      final linkId = linkIds[i];
      
      try {
        // Get current link data
        final linkRows = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
        if (linkRows.isEmpty) {
          errors.add('Link with ID $linkId not found');
          continue;
        }
        
        final currentLink = LinkItem.fromMap(linkRows.first);
        
        // Update link collection in local database
        await db.update(
          'links',
          {
            'collection': toCollection,
            'is_dirty': 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkId],
        );

        // Create sync operation
        final operation = LinkMoveOperation(
          localId: linkId,
          remoteId: currentLink.remoteId,
          url: currentLink.url,
          fromCollection: currentLink.collection,
          toCollection: toCollection,
          markAsSynced: () async {
            await db.update(
              'links',
              {
                'is_dirty': 0,
                'last_synced_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [linkId],
            );
          },
        );
        
        operations.add(operation);
        onProgress?.call(i + 1, linkIds.length);
        
      } catch (e) {
        errors.add('Failed to prepare link $linkId: ${e.toString()}');
      }
    }
    
    if (operations.isEmpty) {
      return SyncResult.immediateFailure(
        'No links could be processed: ${errors.join('; ')}',
        linkIds.map((id) => id.toString()).toList(),
      );
    }
    
    // Execute sync based on user preference
    final strategy = await _getSyncStrategy();
    
    // Create bulk operation for sync
    final bulkOperation = BulkOperation(
      operations: operations,
      onProgress: onProgress,
    );
    
    final result = await strategy.executeSync(bulkOperation);
    
    // Handle partial failures
    if (errors.isNotEmpty) {
      if (result.success) {
        return SyncResult.immediatePartialFailure(
          'Bulk move completed with ${errors.length} errors: ${errors.join('; ')}',
          errors,
        );
      } else {
        return SyncResult.immediateFailure(
          'Bulk move failed: ${result.errorMessage}. Additional errors: ${errors.join('; ')}',
          result.failedItemIds + errors,
        );
      }
    }
    
    return result;
  }

  /// Deletes multiple links with configurable sync behavior and progress tracking
  Future<SyncResult> deleteLinksBulk({
    required List<int> linkIds,
    Function(int completed, int total)? onProgress,
  }) async {
    final db = await AppDb.instance();
    final operations = <LinkDeleteOperation>[];
    final errors = <String>[];
    
    // Prepare all operations
    for (int i = 0; i < linkIds.length; i++) {
      final linkId = linkIds[i];
      
      try {
        // Get current link data before deletion
        final linkRows = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
        if (linkRows.isEmpty) {
          errors.add('Link with ID $linkId not found');
          continue;
        }
        
        final currentLink = LinkItem.fromMap(linkRows.first);
        
        // Create sync operation
        final operation = LinkDeleteOperation(
          localId: linkId,
          remoteId: currentLink.remoteId,
          url: currentLink.url,
        );
        
        operations.add(operation);
        onProgress?.call(i + 1, linkIds.length);
        
      } catch (e) {
        errors.add('Failed to prepare link $linkId for deletion: ${e.toString()}');
      }
    }
    
    if (operations.isEmpty) {
      return SyncResult.immediateFailure(
        'No links could be processed for deletion: ${errors.join('; ')}',
        linkIds.map((id) => id.toString()).toList(),
      );
    }
    
    // Execute sync based on user preference
    final strategy = await _getSyncStrategy();
    
    // Create bulk operation for sync
    final bulkOperation = BulkOperation(
      operations: operations,
      onProgress: onProgress,
    );
    
    final result = await strategy.executeSync(bulkOperation);
    
    // Always delete locally regardless of sync result
    for (final operation in operations) {
      try {
        await db.delete('links', where: 'id = ?', whereArgs: [operation.localId]);
      } catch (e) {
        errors.add('Failed to delete local link ${operation.localId}: ${e.toString()}');
      }
    }
    
    // Handle partial failures
    if (errors.isNotEmpty) {
      if (result.success) {
        return SyncResult.immediatePartialFailure(
          'Bulk delete completed with ${errors.length} errors: ${errors.join('; ')}',
          errors,
        );
      } else {
        return SyncResult.immediateFailure(
          'Bulk delete failed: ${result.errorMessage}. Additional errors: ${errors.join('; ')}',
          result.failedItemIds + errors,
        );
      }
    }
    
    return result;
  }

  /// Moves multiple links with optimized sync behavior, cancellation support, and progress tracking
  /// This demonstrates the new performance optimizations
  Future<SyncResult> moveLinksBulkOptimized({
    required List<int> linkIds,
    String? toCollection,
    CancellationToken? cancellationToken,
    Function(BulkSyncProgress progress)? onProgress,
    int? maxConcurrency,
  }) async {
    final db = await AppDb.instance();
    final operations = <LinkMoveOperation>[];
    final errors = <String>[];
    
    // Prepare all operations
    for (int i = 0; i < linkIds.length; i++) {
      final linkId = linkIds[i];
      
      try {
        // Check for cancellation during preparation
        cancellationToken?.throwIfCancelled();
        
        // Get current link data
        final linkRows = await db.query('links', where: 'id = ?', whereArgs: [linkId]);
        if (linkRows.isEmpty) {
          errors.add('Link with ID $linkId not found');
          continue;
        }
        
        final currentLink = LinkItem.fromMap(linkRows.first);
        
        // Update link collection in local database
        await db.update(
          'links',
          {
            'collection': toCollection,
            'is_dirty': 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkId],
        );

        // Create sync operation
        final operation = LinkMoveOperation(
          localId: linkId,
          remoteId: currentLink.remoteId,
          url: currentLink.url,
          fromCollection: currentLink.collection,
          toCollection: toCollection,
          markAsSynced: () async {
            await db.update(
              'links',
              {
                'is_dirty': 0,
                'last_synced_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [linkId],
            );
          },
        );
        
        operations.add(operation);
        
      } catch (e) {
        if (e is OperationCancelledException) {
          rethrow;
        }
        errors.add('Failed to prepare link $linkId: ${e.toString()}');
      }
    }
    
    if (operations.isEmpty) {
      return SyncResult.immediateFailure(
        'No links could be processed: ${errors.join('; ')}',
        linkIds.map((id) => id.toString()).toList(),
      );
    }
    
    // Use the optimized bulk sync execution with performance enhancements
    final results = await SyncStrategyFactory.executeBulkSyncOptimized(
      operations,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
      maxConcurrency: maxConcurrency ?? 3, // Default to 3 concurrent operations
      enableRetry: true,
    );
    
    // Analyze results
    final successCount = results.where((r) => r.success).length;
    final failureCount = results.length - successCount;
    
    if (failureCount == 0) {
      return SyncResult.immediateSuccess();
    } else if (successCount > 0) {
      return SyncResult.immediatePartialFailure(
        'Bulk move partially completed: $successCount succeeded, $failureCount failed',
        results.where((r) => !r.success).expand((r) => r.failedItemIds).toList(),
      );
    } else {
      return SyncResult.immediateFailure(
        'Bulk move failed completely',
        results.expand((r) => r.failedItemIds).toList(),
      );
    }
  }

  /// Creates a link with optimized sync behavior and cancellation support
  /// This demonstrates the new performance optimizations for single operations
  Future<SyncResult> createLinkOptimized({
    required String url,
    String? title,
    String? description,
    List<String> tags = const [],
    bool isPrivate = true,
    String? collection,
    CancellationToken? cancellationToken,
    Function(SyncProgress progress)? onProgress,
  }) async {
    final db = await AppDb.instance();
    
    // Check for cancellation before starting
    cancellationToken?.throwIfCancelled();
    
    // Insert link into local database first
    final linkId = await db.insert('links', {
      'url': url,
      'title': title,
      'notes': description,
      'tags': tags.join(','),
      'is_private': isPrivate ? 1 : 0,
      'collection': collection,
      'is_dirty': 1, // Always mark as dirty initially
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Create sync operation
    final operation = LinkCreateOperation(
      localId: linkId,
      url: url,
      title: title,
      description: description,
      tags: tags,
      isPrivate: isPrivate,
      collection: collection,
      markAsSynced: (remoteId) async {
        await db.update(
          'links',
          {
            'remote_id': remoteId,
            'is_dirty': 0,
            'last_synced_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [linkId],
        );
      },
    );

    // Use the optimized sync execution with performance enhancements
    final result = await SyncStrategyFactory.executeSyncOptimized(
      operation,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
      enableRetry: true,
      useBackground: false, // Single operations don't need background execution
    );

    // If immediate sync failed, mark as dirty for later sync
    if (!result.success && result.type == SyncResultType.immediateFailure) {
      await db.update(
        'links',
        {'is_dirty': 1, 'last_synced_at': null},
        where: 'id = ?',
        whereArgs: [linkId],
      );
    }

    return result;
  }

  /// Cancels a running sync operation by its operation ID
  static void cancelSync(String operationId, [String? reason]) {
    SyncStrategyFactory.cancelSync(operationId, reason);
  }

  /// Cancels all running sync operations
  static void cancelAllSyncs([String? reason]) {
    SyncStrategyFactory.cancelAllSyncs(reason);
  }

  /// Gets the list of currently active sync operation IDs
  static List<String> getActiveSyncIds() {
    return SyncStrategyFactory.getActiveSyncIds();
  }

  /// Checks if a specific sync operation is currently running
  static bool isSyncRunning(String operationId) {
    return SyncStrategyFactory.isSyncRunning(operationId);
  }

  /// Formats a sync result into a user-friendly message
  static String formatSyncResultMessage(SyncResult result, String operationName) {
    switch (result.type) {
      case SyncResultType.immediateSuccess:
        return '$operationName and synced successfully';
      case SyncResultType.immediateFailure:
        return '$operationName locally, but server sync failed: ${result.errorMessage}';
      case SyncResultType.immediatePartialFailure:
        return '$operationName partially synced. Some items failed: ${result.errorMessage}';
      case SyncResultType.manualQueued:
        return '$operationName locally. Use sync to upload changes.';
    }
  }
}
