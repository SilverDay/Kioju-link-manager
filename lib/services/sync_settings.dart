import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// Service for managing sync preferences and settings
class SyncSettings {
  static const String _immediateSyncKey = 'immediate_sync_enabled';
  
  // Cache to avoid repeated storage calls
  static bool? _cachedImmediateSyncEnabled;
  
  // Cache expiry timer to refresh cache periodically
  static Timer? _cacheExpiryTimer;
  static const Duration _cacheExpiryDuration = Duration(minutes: 5);

  /// Gets whether immediate sync is enabled
  /// Defaults to false (manual sync) for new installations
  static Future<bool> isImmediateSyncEnabled() async {
    // Return cached value if available and not expired
    if (_cachedImmediateSyncEnabled != null) {
      return _cachedImmediateSyncEnabled!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // Default to manual sync mode for new installations
      _cachedImmediateSyncEnabled = prefs.getBool(_immediateSyncKey) ?? false;
      
      // Set cache expiry timer
      _resetCacheExpiryTimer();
      
      return _cachedImmediateSyncEnabled!;
    } catch (e) {
      // Default to manual sync on error
      _cachedImmediateSyncEnabled = false;
      return false;
    }
  }

  /// Sets whether immediate sync is enabled
  static Future<void> setImmediateSyncEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_immediateSyncKey, enabled);
      // Update cache immediately
      _cachedImmediateSyncEnabled = enabled;
      // Reset cache expiry timer
      _resetCacheExpiryTimer();
    } catch (e) {
      // Re-throw to allow caller to handle error
      throw Exception('Failed to save immediate sync preference: $e');
    }
  }

  /// Clears the sync preference cache (useful for testing or reset)
  static void clearCache() {
    _cachedImmediateSyncEnabled = null;
    _cacheExpiryTimer?.cancel();
    _cacheExpiryTimer = null;
  }

  /// Clears all sync settings (useful for logout/reset)
  static Future<void> clearAllSyncSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_immediateSyncKey);
      clearCache();
    } catch (e) {
      // Silently fail - non-critical operation
    }
  }

  /// Resets the cache expiry timer
  static void _resetCacheExpiryTimer() {
    _cacheExpiryTimer?.cancel();
    _cacheExpiryTimer = Timer(_cacheExpiryDuration, () {
      _cachedImmediateSyncEnabled = null;
    });
  }
}
