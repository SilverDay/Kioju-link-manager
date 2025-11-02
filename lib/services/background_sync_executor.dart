import 'dart:async';
import 'sync_strategy.dart';
import 'cancellation_token.dart';
import 'sync_retry_service.dart';

/// Handles background execution of sync operations with threading support
class BackgroundSyncExecutor {
  static final Map<String, CancellationToken> _activeSyncs = {};
  static final Map<String, StreamController<SyncProgress>>
  _progressControllers = {};

  /// Executes a sync operation in the background with cancellation support
  ///
  /// [operation] - The sync operation to execute
  /// [strategy] - The sync strategy to use
  /// [cancellationToken] - Optional cancellation token
  /// [onProgress] - Optional progress callback
  /// [enableRetry] - Whether to enable retry logic (default: true)
  static Future<SyncResult> executeInBackground(
    SyncOperation operation,
    SyncStrategy strategy, {
    CancellationToken? cancellationToken,
    Function(SyncProgress progress)? onProgress,
    bool enableRetry = true,
  }) async {
    final operationId = operation.operationId;

    // Check if operation is already running
    if (_activeSyncs.containsKey(operationId)) {
      throw Exception('Sync operation $operationId is already running');
    }

    // Create or use provided cancellation token
    final token = cancellationToken ?? CancellationToken();
    _activeSyncs[operationId] = token;

    // Create progress controller if progress callback is provided
    StreamController<SyncProgress>? progressController;
    if (onProgress != null) {
      progressController = StreamController<SyncProgress>.broadcast();
      _progressControllers[operationId] = progressController;
      progressController.stream.listen(onProgress);
    }

    try {
      // Report start progress
      progressController?.add(SyncProgress.started(operationId));

      // Execute the sync operation
      final result = await _executeSyncWithRetry(
        operation,
        strategy,
        token,
        progressController,
        enableRetry,
      );

      // Report completion progress
      if (result.success) {
        progressController?.add(SyncProgress.completed(operationId));
      } else {
        progressController?.add(
          SyncProgress.failed(operationId, result.errorMessage),
        );
      }

      return result;
    } catch (e) {
      // Report error progress
      progressController?.add(SyncProgress.failed(operationId, e.toString()));
      rethrow;
    } finally {
      // Clean up
      _activeSyncs.remove(operationId);
      _progressControllers.remove(operationId);
      await progressController?.close();
    }
  }

  /// Cancels a running sync operation
  static void cancelSync(String operationId, [String? reason]) {
    final token = _activeSyncs[operationId];
    if (token != null) {
      token.cancel(reason ?? 'Sync operation cancelled by user');
    }
  }

  /// Cancels all running sync operations
  static void cancelAllSyncs([String? reason]) {
    final tokens = List<CancellationToken>.from(_activeSyncs.values);
    for (final token in tokens) {
      token.cancel(reason ?? 'All sync operations cancelled');
    }
  }

  /// Gets the list of currently active sync operation IDs
  static List<String> getActiveSyncIds() {
    return _activeSyncs.keys.toList();
  }

  /// Checks if a specific sync operation is currently running
  static bool isSyncRunning(String operationId) {
    return _activeSyncs.containsKey(operationId);
  }

  /// Executes sync with retry logic and cancellation support
  static Future<SyncResult> _executeSyncWithRetry(
    SyncOperation operation,
    SyncStrategy strategy,
    CancellationToken cancellationToken,
    StreamController<SyncProgress>? progressController,
    bool enableRetry,
  ) async {
    if (!enableRetry) {
      // Execute without retry
      cancellationToken.throwIfCancelled();
      return await strategy.executeSync(operation);
    }

    // Execute with retry logic
    return await SyncRetryService.executeWithRetry(
      () async {
        cancellationToken.throwIfCancelled();
        return await strategy.executeSync(operation);
      },
      onRetry: (attempt, error) {
        progressController?.add(
          SyncProgress.retrying(
            operation.operationId,
            attempt,
            error.toString(),
          ),
        );
      },
      shouldRetry: (error) {
        // Don't retry if cancelled
        if (error is OperationCancelledException) {
          return false;
        }
        return SyncRetryService.shouldRetryError(error);
      },
    );
  }

  /// Executes multiple sync operations concurrently with progress tracking
  static Future<List<SyncResult>> executeBulkInBackground(
    List<SyncOperation> operations,
    SyncStrategy strategy, {
    CancellationToken? cancellationToken,
    Function(BulkSyncProgress progress)? onProgress,
    int? maxConcurrency,
    bool enableRetry = true,
  }) async {
    final token = cancellationToken ?? CancellationToken();
    final concurrency =
        maxConcurrency ?? 3; // Default to 3 concurrent operations
    final results = <SyncResult>[];
    final errors = <String>[];

    int completed = 0;
    int failed = 0;

    // Report initial progress
    onProgress?.call(
      BulkSyncProgress(
        totalOperations: operations.length,
        completedOperations: 0,
        failedOperations: 0,
        currentOperation: null,
        isCompleted: false,
      ),
    );

    // Process operations in batches to limit concurrency
    for (int i = 0; i < operations.length; i += concurrency) {
      token.throwIfCancelled();

      final batch = operations.skip(i).take(concurrency).toList();
      final batchFutures = batch.map((operation) async {
        try {
          onProgress?.call(
            BulkSyncProgress(
              totalOperations: operations.length,
              completedOperations: completed,
              failedOperations: failed,
              currentOperation: operation.operationId,
              isCompleted: false,
            ),
          );

          final result = await executeInBackground(
            operation,
            strategy,
            cancellationToken: token,
            enableRetry: enableRetry,
          );

          if (result.success) {
            completed++;
          } else {
            failed++;
            errors.add('${operation.operationId}: ${result.errorMessage}');
          }

          return result;
        } catch (e) {
          failed++;
          errors.add('${operation.operationId}: ${e.toString()}');
          return SyncResult.immediateFailure(e.toString(), [
            operation.operationId,
          ]);
        }
      });

      final batchResults = await Future.wait(batchFutures);
      results.addAll(batchResults);
    }

    // Report final progress
    onProgress?.call(
      BulkSyncProgress(
        totalOperations: operations.length,
        completedOperations: completed,
        failedOperations: failed,
        currentOperation: null,
        isCompleted: true,
        errors: errors,
      ),
    );

    return results;
  }
}

/// Represents progress of a sync operation
class SyncProgress {
  final String operationId;
  final SyncProgressType type;
  final String? message;
  final int? retryAttempt;

  const SyncProgress({
    required this.operationId,
    required this.type,
    this.message,
    this.retryAttempt,
  });

  factory SyncProgress.started(String operationId) {
    return SyncProgress(
      operationId: operationId,
      type: SyncProgressType.started,
    );
  }

  factory SyncProgress.completed(String operationId) {
    return SyncProgress(
      operationId: operationId,
      type: SyncProgressType.completed,
    );
  }

  factory SyncProgress.failed(String operationId, String? error) {
    return SyncProgress(
      operationId: operationId,
      type: SyncProgressType.failed,
      message: error,
    );
  }

  factory SyncProgress.retrying(String operationId, int attempt, String error) {
    return SyncProgress(
      operationId: operationId,
      type: SyncProgressType.retrying,
      message: error,
      retryAttempt: attempt,
    );
  }
}

enum SyncProgressType { started, completed, failed, retrying }

/// Represents progress of bulk sync operations
class BulkSyncProgress {
  final int totalOperations;
  final int completedOperations;
  final int failedOperations;
  final String? currentOperation;
  final bool isCompleted;
  final List<String>? errors;

  const BulkSyncProgress({
    required this.totalOperations,
    required this.completedOperations,
    required this.failedOperations,
    this.currentOperation,
    required this.isCompleted,
    this.errors,
  });

  double get progressPercentage {
    if (totalOperations == 0) return 0.0;
    return (completedOperations + failedOperations) / totalOperations;
  }

  int get remainingOperations {
    return totalOperations - completedOperations - failedOperations;
  }
}
