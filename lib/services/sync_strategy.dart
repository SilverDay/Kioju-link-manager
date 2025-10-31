/// Represents the result of a sync operation
class SyncResult {
  final bool success;
  final String? errorMessage;
  final List<String> failedItemIds;
  final SyncResultType type;

  const SyncResult({
    required this.success,
    this.errorMessage,
    this.failedItemIds = const [],
    required this.type,
  });

  /// Creates a successful immediate sync result
  factory SyncResult.immediateSuccess() {
    return const SyncResult(
      success: true,
      type: SyncResultType.immediateSuccess,
    );
  }

  /// Creates a failed immediate sync result
  factory SyncResult.immediateFailure(String errorMessage, [List<String>? failedIds]) {
    return SyncResult(
      success: false,
      errorMessage: errorMessage,
      failedItemIds: failedIds ?? [],
      type: SyncResultType.immediateFailure,
    );
  }

  /// Creates a partial failure immediate sync result
  factory SyncResult.immediatePartialFailure(String errorMessage, List<String> failedIds) {
    return SyncResult(
      success: false,
      errorMessage: errorMessage,
      failedItemIds: failedIds,
      type: SyncResultType.immediatePartialFailure,
    );
  }

  /// Creates a manual sync queued result
  factory SyncResult.manualQueued() {
    return const SyncResult(
      success: true,
      type: SyncResultType.manualQueued,
    );
  }
}

/// Types of sync results
enum SyncResultType {
  immediateSuccess,
  immediatePartialFailure,
  immediateFailure,
  manualQueued,
}

/// Base class for sync operations
abstract class SyncOperation {
  /// Unique identifier for the operation
  String get operationId;
  
  /// Type of operation for logging/debugging
  String get operationType;
}

/// Abstract base class for sync strategies
abstract class SyncStrategy {
  /// Executes a sync operation according to the strategy
  Future<SyncResult> executeSync(SyncOperation operation);
}
