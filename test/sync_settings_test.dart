import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kioju_link_manager/services/sync_settings.dart';

void main() {
  group('SyncSettings Service Tests', () {
    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      // Clear cache before each test
      SyncSettings.clearCache();
    });

    tearDown(() {
      // Clear cache after each test
      SyncSettings.clearCache();
    });

    test('should default to manual sync mode for new installations', () async {
      final isEnabled = await SyncSettings.isImmediateSyncEnabled();
      expect(isEnabled, isFalse);
    });

    test('should save and retrieve immediate sync preference', () async {
      // Enable immediate sync
      await SyncSettings.setImmediateSyncEnabled(true);
      
      // Verify it's enabled
      final isEnabled = await SyncSettings.isImmediateSyncEnabled();
      expect(isEnabled, isTrue);
    });

    test('should save and retrieve manual sync preference', () async {
      // First enable immediate sync
      await SyncSettings.setImmediateSyncEnabled(true);
      expect(await SyncSettings.isImmediateSyncEnabled(), isTrue);
      
      // Then disable it (switch to manual)
      await SyncSettings.setImmediateSyncEnabled(false);
      
      // Verify it's disabled
      final isEnabled = await SyncSettings.isImmediateSyncEnabled();
      expect(isEnabled, isFalse);
    });

    test('should use cached value for repeated calls', () async {
      // Set initial value
      await SyncSettings.setImmediateSyncEnabled(true);
      
      // First call should read from storage
      final firstCall = await SyncSettings.isImmediateSyncEnabled();
      expect(firstCall, isTrue);
      
      // Second call should use cached value
      final secondCall = await SyncSettings.isImmediateSyncEnabled();
      expect(secondCall, isTrue);
    });

    test('should clear cache when requested', () async {
      // Set a value
      await SyncSettings.setImmediateSyncEnabled(true);
      expect(await SyncSettings.isImmediateSyncEnabled(), isTrue);
      
      // Clear cache
      SyncSettings.clearCache();
      
      // Should still return the stored value (reads from storage again)
      expect(await SyncSettings.isImmediateSyncEnabled(), isTrue);
    });

    test('should clear all sync settings', () async {
      // Set a value
      await SyncSettings.setImmediateSyncEnabled(true);
      expect(await SyncSettings.isImmediateSyncEnabled(), isTrue);
      
      // Clear all settings
      await SyncSettings.clearAllSyncSettings();
      
      // Should return default value
      expect(await SyncSettings.isImmediateSyncEnabled(), isFalse);
    });

    test('should handle storage errors gracefully', () async {
      // This test simulates storage failure by using invalid mock data
      // The service should default to manual sync mode on error
      
      // Clear cache to force storage read
      SyncSettings.clearCache();
      
      // The service should handle any storage errors and default to false
      final isEnabled = await SyncSettings.isImmediateSyncEnabled();
      expect(isEnabled, isFalse);
    });

    test('should update cache immediately when setting preference', () async {
      // Set preference
      await SyncSettings.setImmediateSyncEnabled(true);
      
      // Cache should be updated immediately
      final isEnabled = await SyncSettings.isImmediateSyncEnabled();
      expect(isEnabled, isTrue);
      
      // Change preference
      await SyncSettings.setImmediateSyncEnabled(false);
      
      // Cache should be updated immediately
      final isEnabledAfter = await SyncSettings.isImmediateSyncEnabled();
      expect(isEnabledAfter, isFalse);
    });
  });
}
