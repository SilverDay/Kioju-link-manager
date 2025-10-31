import '../db.dart';
import '../utils/bookmark_import.dart';
import 'sync_settings.dart';
import 'sync_strategy.dart';
import 'immediate_sync_strategy.dart';
import 'manual_sync_strategy.dart';

/// Result of an import operation with sync information
class ImportSyncResult {
  final ImportResult importResult;
  final int totalLinksProcessed;
  final int linksSuccessfullySynced;
  final int linksMarkedForSync;
  final List<String> syncErrors;
  final bool isImmediateSync;

  ImportSyncResult({
    required this.importResult,
    required this.totalLinksProcessed,
    required this.linksSuccessfullySynced,
    required this.linksMarkedForSync,
    required this.syncErrors,
    required this.isImmediateSync,
  });

  /// Whether the import was completely successful
  bool get isCompleteSuccess => syncErrors.isEmpty;

  /// Whether the import had partial failures
  bool get hasPartialFailures =>
      syncErrors.isNotEmpty &&
      (linksSuccessfullySynced > 0 || linksMarkedForSync > 0);

  /// Whether the import failed completely
  bool get isCompleteFailure =>
      linksSuccessfullySynced == 0 &&
      linksMarkedForSync == 0 &&
      syncErrors.isNotEmpty;

  /// Get a user-friendly status message
  String get statusMessage {
    if (isCompleteSuccess) {
      if (isImmediateSync) {
        return 'All $totalLinksProcessed links imported and synced successfully';
      } else {
        return 'All $totalLinksProcessed links imported locally. Use sync to upload to server.';
      }
    } else if (hasPartialFailures) {
      if (isImmediateSync) {
        return '$linksSuccessfullySynced of $totalLinksProcessed links synced successfully. ${syncErrors.length} failed and were saved locally.';
      } else {
        return '$linksMarkedForSync of $totalLinksProcessed links saved locally. ${syncErrors.length} failed to save.';
      }
    } else {
      return 'Import failed: ${syncErrors.join('; ')}';
    }
  }
}

/// Service for handling bookmark imports with configurable sync behavior
class ImportService {
  static ImportService? _instance;

  static ImportService get instance {
    _instance ??= ImportService._();
    return _instance!;
  }

  ImportService._();

  /// Import bookmarks from HTML content with configurable sync
  Future<ImportSyncResult> importFromHtml(
    String htmlContent, {
    bool createCollections = true,
    Map<String, String>? collectionNameMappings,
    Function(int completed, int total)? onProgress,
  }) async {
    // Parse bookmarks first
    final importResult = await importFromNetscapeHtml(
      htmlContent,
      createCollections: createCollections,
      collectionNameMappings: collectionNameMappings,
    );

    // Import links with sync strategy
    return await importLinksWithSync(importResult, onProgress);
  }

  /// Import bookmarks from JSON content with configurable sync
  Future<ImportSyncResult> importFromJson(
    Map<String, dynamic> jsonContent, {
    bool createCollections = true,
    Map<String, String>? collectionNameMappings,
    Function(int completed, int total)? onProgress,
  }) async {
    // Parse bookmarks first
    final importResult = await importFromChromeJson(
      jsonContent,
      createCollections: createCollections,
      collectionNameMappings: collectionNameMappings,
    );

    // Import links with sync strategy
    return await importLinksWithSync(importResult, onProgress);
  }

  /// Import links using the configured sync strategy
  Future<ImportSyncResult> importLinksWithSync(
    ImportResult importResult,
    Function(int completed, int total)? onProgress,
  ) async {
    if (importResult.bookmarks.isEmpty) {
      return ImportSyncResult(
        importResult: importResult,
        totalLinksProcessed: 0,
        linksSuccessfullySynced: 0,
        linksMarkedForSync: 0,
        syncErrors: [],
        isImmediateSync: false,
      );
    }

    // Get sync preference
    final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
    final SyncStrategy strategy =
        isImmediateSync ? ImmediateSyncStrategy() : ManualSyncStrategy();

    // Insert links into local database first
    final db = await AppDb.instance();
    final linkDataList = <Map<String, dynamic>>[];

    for (final bookmark in importResult.bookmarks) {
      try {
        // Insert link into database
        final linkId = await db.insert('links', {
          'url': bookmark.url,
          'title': bookmark.title,
          'tags': bookmark.tags.join(','),
          'collection': bookmark.collection,
          'is_dirty': 1, // Always start as dirty
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Add to sync operation data
        linkDataList.add({
          'localId': linkId,
          'url': bookmark.url,
          'title': bookmark.title,
          'tags': bookmark.tags,
          'collection': bookmark.collection,
        });
      } catch (e) {
        // Skip links that fail to insert locally
        continue;
      }
    }

    if (linkDataList.isEmpty) {
      return ImportSyncResult(
        importResult: importResult,
        totalLinksProcessed: importResult.bookmarks.length,
        linksSuccessfullySynced: 0,
        linksMarkedForSync: 0,
        syncErrors: ['Failed to save any links to local database'],
        isImmediateSync: isImmediateSync,
      );
    }

    // Create import operation for sync
    final importOperation = ImportOperation(
      importedLinks: linkDataList,
      onProgress: onProgress,
    );

    // Execute sync strategy
    final syncResult = await strategy.executeSync(importOperation);

    // Parse results
    int linksSuccessfullySynced = 0;
    int linksMarkedForSync = 0;
    final syncErrors = <String>[];

    if (syncResult.success) {
      if (isImmediateSync) {
        linksSuccessfullySynced = linkDataList.length;
      } else {
        linksMarkedForSync = linkDataList.length;
      }
    } else {
      // Handle partial or complete failures
      if (syncResult.errorMessage != null) {
        syncErrors.add(syncResult.errorMessage!);
      }

      if (isImmediateSync) {
        // For immediate sync failures, count successful vs failed
        final failedCount = syncResult.failedItemIds.length;
        linksSuccessfullySynced = linkDataList.length - failedCount;
        linksMarkedForSync =
            failedCount; // Failed items are marked for later sync
      } else {
        // For manual sync, if there's an error, nothing was marked for sync
        linksMarkedForSync = 0;
      }
    }

    return ImportSyncResult(
      importResult: importResult,
      totalLinksProcessed: linkDataList.length,
      linksSuccessfullySynced: linksSuccessfullySynced,
      linksMarkedForSync: linksMarkedForSync,
      syncErrors: syncErrors,
      isImmediateSync: isImmediateSync,
    );
  }
}
