import 'dart:async';

/// Exception thrown when an operation is cancelled
class OperationCancelledException implements Exception {
  final String message;
  
  const OperationCancelledException([this.message = 'Operation was cancelled']);
  
  @override
  String toString() => 'OperationCancelledException: $message';
}

/// Token that can be used to cancel long-running operations
class CancellationToken {
  final Completer<void> _completer = Completer<void>();
  bool _isCancelled = false;
  String? _reason;

  /// Creates a new cancellation token
  CancellationToken();

  /// Creates a cancellation token that is already cancelled
  CancellationToken.cancelled([String? reason]) {
    _cancel(reason);
  }

  /// Whether this token has been cancelled
  bool get isCancelled => _isCancelled;

  /// The reason for cancellation, if any
  String? get reason => _reason;

  /// Future that completes when the token is cancelled
  Future<void> get cancelled => _completer.future;

  /// Cancels the token with an optional reason
  void cancel([String? reason]) {
    if (!_isCancelled) {
      _cancel(reason);
    }
  }

  void _cancel(String? reason) {
    _isCancelled = true;
    _reason = reason;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Throws OperationCancelledException if the token is cancelled
  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCancelledException(_reason ?? 'Operation was cancelled');
    }
  }

  /// Creates a new token that will be cancelled when any of the provided tokens are cancelled
  static CancellationToken any(List<CancellationToken> tokens) {
    final combinedToken = CancellationToken();
    
    for (final token in tokens) {
      if (token.isCancelled) {
        combinedToken._cancel(token.reason);
        break;
      } else {
        token.cancelled.then((_) {
          if (!combinedToken.isCancelled) {
            combinedToken._cancel(token.reason ?? 'Combined token cancelled');
          }
        });
      }
    }
    
    return combinedToken;
  }

  /// Creates a token that will be cancelled after the specified timeout
  static CancellationToken timeout(Duration timeout) {
    final token = CancellationToken();
    Timer(timeout, () {
      token.cancel('Operation timed out after ${timeout.inSeconds} seconds');
    });
    return token;
  }
}

/// Mixin that provides cancellation support to operations
mixin CancellationSupport {
  CancellationToken? _cancellationToken;

  /// Sets the cancellation token for this operation
  void setCancellationToken(CancellationToken? token) {
    _cancellationToken = token;
  }

  /// Gets the current cancellation token
  CancellationToken? get cancellationToken => _cancellationToken;

  /// Throws if the operation has been cancelled
  void checkCancellation() {
    _cancellationToken?.throwIfCancelled();
  }

  /// Executes an async operation with cancellation support
  Future<T> executeWithCancellation<T>(Future<T> Function() operation) async {
    checkCancellation();
    
    if (_cancellationToken == null) {
      return await operation();
    }
    
    // Race between the operation and cancellation
    final result = await Future.any([
      operation(),
      _cancellationToken!.cancelled.then<T>((_) {
        throw OperationCancelledException(_cancellationToken!.reason ?? 'Operation cancelled');
      }),
    ]);
    
    return result;
  }
}
