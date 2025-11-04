import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class AppSettings {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: const LinuxOptions(),
    wOptions: const WindowsOptions(),
    mOptions: const MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accessGroup: AppConstants.macosKeychainAccessGroup,
    ),
  );

  static const String _autoFetchMetadataKey = 'auto_fetch_metadata';

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

  /// Clears all app settings (useful for logout/reset)
  static Future<void> clearAllSettings() async {
    try {
      await _storage.delete(key: _autoFetchMetadataKey);
    } catch (e) {
      // Silently fail
    }
  }
}
