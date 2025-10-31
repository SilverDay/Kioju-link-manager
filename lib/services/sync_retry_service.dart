import 'dart:async';
import 'dart:math';

/// Service for handling retry logic with exponential backoff for sync operations
class SyncRetryService {
  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);
  static const double _backoffMultiplier = 2.0;
  static const double _jitterFactor = 0.1;

  /// Executes a function with retry logic and exponential backoff
  /// 
  /// [operation] - The async function to execute
  /// [maxRetries] - Maximum number of retry attempts (default: 3)
  /// [baseDelay] - Base delay between retries (default: 1 second)
  /// [onRetry] - Optional callback called before each retry attempt
  /// [shouldRetry] - Optional function to determine if error should trigger retry
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int? maxRetries,
    Duration? baseDelay,
    Function(int attempt, Exception error)? onRetry,
    bool Function(Exception error)? shouldRetry,
  }) async {
    final maxAttempts = (maxRetries ?? _maxRetries) + 1; // +1 for initial attempt
    final delay = baseDelay ?? _baseDelay;
    
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (e) {
        final exception = e is Exception ? e : Exception(e.toString());
        
        // Check if we should retry this error
        if (shouldRetry != null && !shouldRetry(exception)) {
          rethrow;
        }
        
        // If this was the last attempt, rethrow the error
        if (attempt == maxAttempts) {
          rethrow;
        }
        
        // Calculate delay with exponential backoff and jitter
        final retryDelay = _calculateDelay(attempt - 1, delay);
        
        // Call retry callback if provided
        onRetry?.call(attempt, exception);
        
        // Wait before retrying
        await Future.delayed(retryDelay);
      }
    }
    
    // This should never be reached, but satisfies the analyzer
    throw Exception('Unexpected end of retry loop');
  }

  /// Calculates the delay for a retry attempt with exponential backoff and jitter
  static Duration _calculateDelay(int retryAttempt, Duration baseDelay) {
    // Calculate exponential backoff
    final exponentialDelay = baseDelay.inMilliseconds * 
        pow(_backoffMultiplier, retryAttempt);
    
    // Apply maximum delay cap
    final cappedDelay = min(exponentialDelay, _maxDelay.inMilliseconds.toDouble());
    
    // Add jitter to avoid thundering herd problem
    final jitter = cappedDelay * _jitterFactor * (Random().nextDouble() - 0.5);
    final finalDelay = cappedDelay + jitter;
    
    return Duration(milliseconds: max(0, finalDelay.round()));
  }

  /// Determines if an error should trigger a retry based on common network/server errors
  static bool shouldRetryError(Exception error) {
    final errorMessage = error.toString().toLowerCase();
    
    // Retry on network connectivity issues
    if (errorMessage.contains('network') ||
        errorMessage.contains('connection') ||
        errorMessage.contains('timeout') ||
        errorMessage.contains('unreachable')) {
      return true;
    }
    
    // Retry on server errors (5xx)
    if (errorMessage.contains('server error') ||
        errorMessage.contains('internal server error') ||
        errorMessage.contains('service unavailable') ||
        errorMessage.contains('bad gateway') ||
        errorMessage.contains('gateway timeout')) {
      return true;
    }
    
    // Retry on temporary API rate limiting
    if (errorMessage.contains('rate limit') ||
        errorMessage.contains('too many requests')) {
      return true;
    }
    
    // Don't retry on authentication errors (4xx client errors)
    if (errorMessage.contains('unauthorized') ||
        errorMessage.contains('forbidden') ||
        errorMessage.contains('not found') ||
        errorMessage.contains('bad request')) {
      return false;
    }
    
    // Default to retry for unknown errors
    return true;
  }
}
