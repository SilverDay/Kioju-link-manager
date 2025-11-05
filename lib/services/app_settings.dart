import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class AppSettings {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: LinuxOptions(),
    wOptions: WindowsOptions(),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      groupId: AppConstants.macosKeychainAccessGroup,
    ),
  );

  static const String _autoFetchMetadataKey = 'auto_fetch_metadata';
  static const String _autoSaveExportKey = 'auto_save_export';
  static const String _lastExportPathKey = 'last_export_path';
  static const String _importSyncModeKey = 'import_sync_mode';

  /// Gets whether automatic metadata fetching is enabled
  /// Defaults to true for new installations
  static Future<bool> getAutoFetchMetadata() async {
    try {
      final value = await _storage.read(key: _autoFetchMetadataKey);
      if (value == null) {
        // Default to enabled for new users
        return true;
      }
      return value.toLowerCase() == 'true';
    } catch (e) {
      // Default to enabled on error
      return true;
    }
  }

  /// Sets whether automatic metadata fetching is enabled
  static Future<void> setAutoFetchMetadata(bool enabled) async {
    try {
      await _storage.write(
        key: _autoFetchMetadataKey,
        value: enabled.toString(),
      );
    } catch (e) {
      // Silently fail - non-critical setting
    }
  }

  /// Gets whether automatic export saving is enabled
  /// When enabled, exports automatically update the last used bookmark file
  /// Defaults to false for new installations
  static Future<bool> getAutoSaveExport() async {
    try {
      final value = await _storage.read(key: _autoSaveExportKey);
      if (value == null) {
        return false; // Default to manual save
      }
      return value.toLowerCase() == 'true';
    } catch (e) {
      return false;
    }
  }

  /// Sets whether automatic export saving is enabled
  static Future<void> setAutoSaveExport(bool enabled) async {
    try {
      await _storage.write(key: _autoSaveExportKey, value: enabled.toString());
    } catch (e) {
      // Silently fail - non-critical setting
    }
  }

  /// Gets the last used export file path
  static Future<String?> getLastExportPath() async {
    try {
      return await _storage.read(key: _lastExportPathKey);
    } catch (e) {
      return null;
    }
  }

  /// Sets the last used export file path
  static Future<void> setLastExportPath(String? path) async {
    try {
      if (path != null) {
        await _storage.write(key: _lastExportPathKey, value: path);
      } else {
        await _storage.delete(key: _lastExportPathKey);
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Gets the import sync mode preference
  /// 'follow_global' - Follow the global sync setting
  /// 'manual' - Always use manual sync for imports
  /// 'immediate' - Always use immediate sync for imports
  /// Defaults to 'follow_global'
  static Future<String> getImportSyncMode() async {
    try {
      final value = await _storage.read(key: _importSyncModeKey);
      return value ?? 'follow_global';
    } catch (e) {
      return 'follow_global';
    }
  }

  /// Sets the import sync mode preference
  static Future<void> setImportSyncMode(String mode) async {
    try {
      await _storage.write(key: _importSyncModeKey, value: mode);
    } catch (e) {
      // Silently fail - non-critical setting
    }
  }

  /// Clears all app settings (useful for logout/reset)
  static Future<void> clearAllSettings() async {
    try {
      await _storage.delete(key: _autoFetchMetadataKey);
      await _storage.delete(key: _autoSaveExportKey);
      await _storage.delete(key: _lastExportPathKey);
      await _storage.delete(key: _importSyncModeKey);
    } catch (e) {
      // Silently fail
    }
  }
}
