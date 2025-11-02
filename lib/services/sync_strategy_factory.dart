import 'sync_strategy.dart';
import 'immediate_sync_strategy.dart';
import 'manual_sync_strategy.dart';
import 'sync_settings.dart';
import 'background_sync_executor.dart';
import 'cancellation_token.dart';

/// Factory class for creating the appropriate sync strategy based on user preferences
class SyncStrategyFactory {
  static ImmediateSyncStrategy? _immediateSyncStrategy;
  static ManualSyncStrategy? _manualSyncStrategy;

  /// Gets the appropriate sync strategy based on current user preference
  static Future<SyncStrategy> getStrategy() async {
    final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();

    if (isImmediateSync) {
      // Use singleton pattern to avoid creating multiple instances
      _immediateSyncStrategy ??= ImmediateSyncStrategy();
      return _immediateSyncStrategy!;
    } else {
      // Use singleton pattern to avoid creating multiple instances
      _manualSyncStrategy ??= ManualSyncStrategy();
      return _manualSyncStrategy!;
    }
  }

  /// Executes a sync operation using the appropriate strategy
  static Future<SyncResult> executeSync(SyncOperation operation) async {
    final strategy = await getStrategy();
    return await strategy.executeSync(operation);
  }

  /// Executes a sync operation in the background with performance optimizations
  ///
  /// [operation] - The sync operation to execute
  /// [cancellationToken] - Optional cancellation token
  /// [onProgress] - Optional progress callback
  /// [enableRetry] - Whether to enable retry logic (default: true)
  /// [useBackground] - Whether to use background execution (default: true for bulk/import operations)
  static Future<SyncResult> executeSyncOptimized(
    SyncOperation operation, {
    CancellationToken? cancellationToken,
    Function(SyncProgress progress)? onProgress,
    bool enableRetry = true,
    bool? useBackground,
  }) async {
    final strategy = await getStrategy();

    // Determine if we should use background execution
    final shouldUseBackground =
        useBackground ??
        (operation is BulkOperation || operation is ImportOperation);

    if (shouldUseBackground) {
      // Set cancellation token on strategy if it supports it
      if (strategy is ImmediateSyncStrategy) {
        strategy.setCancellationToken(cancellationToken);
      }

      return await BackgroundSyncExecutor.executeInBackground(
        operation,
        strategy,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
        enableRetry: enableRetry,
      );
    } else {
      // Execute directly for simple operations
      if (strategy is ImmediateSyncStrategy) {
        strategy.setCancellationToken(cancellationToken);
      }
      return await strategy.executeSync(operation);
    }
  }

  /// Executes multiple sync operations concurrently with progress tracking
  static Future<List<SyncResult>> executeBulkSyncOptimized(
    List<SyncOperation> operations, {
    CancellationToken? cancellationToken,
    Function(BulkSyncProgress progress)? onProgress,
    int? maxConcurrency,
    bool enableRetry = true,
  }) async {
    final strategy = await getStrategy();

    return await BackgroundSyncExecutor.executeBulkInBackground(
      operations,
      strategy,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
      maxConcurrency: maxConcurrency,
      enableRetry: enableRetry,
    );
  }

  /// Cancels a running sync operation
  static void cancelSync(String operationId, [String? reason]) {
    BackgroundSyncExecutor.cancelSync(operationId, reason);
  }

  /// Cancels all running sync operations
  static void cancelAllSyncs([String? reason]) {
    BackgroundSyncExecutor.cancelAllSyncs(reason);
  }

  /// Gets the list of currently active sync operation IDs
  static List<String> getActiveSyncIds() {
    return BackgroundSyncExecutor.getActiveSyncIds();
  }

  /// Checks if a specific sync operation is currently running
  static bool isSyncRunning(String operationId) {
    return BackgroundSyncExecutor.isSyncRunning(operationId);
  }

  /// Clears cached strategy instances (useful for testing)
  static void clearCache() {
    _immediateSyncStrategy = null;
    _manualSyncStrategy = null;
  }
}
