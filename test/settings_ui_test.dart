import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kioju_link_manager/pages/settings_page.dart';
import 'package:kioju_link_manager/services/sync_settings.dart';

void main() {
  group('Settings UI Tests', () {
    setUp(() async {
      // Initialize Flutter binding for tests
      TestWidgetsFlutterBinding.ensureInitialized();

      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      SyncSettings.clearCache();
    });

    tearDown(() async {
      SyncSettings.clearCache();
      // Allow any pending timers to complete
      await Future.delayed(Duration.zero);
    });

    testWidgets('should display settings page with App Preferences section', (
      WidgetTester tester,
    ) async {
      // Build the settings page with a larger screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(MaterialApp(home: const SettingsPage()));

      // Wait for the page to load
      await tester.pumpAndSettle();

      // Verify the app preferences section is present
      expect(find.text('App Preferences'), findsOneWidget);
    });

    testWidgets('should display API Configuration section', (
      WidgetTester tester,
    ) async {
      // Build the settings page with a larger screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(MaterialApp(home: const SettingsPage()));

      // Wait for the page to load
      await tester.pumpAndSettle();

      // Verify API Configuration section is present
      expect(find.text('API Configuration'), findsOneWidget);
    });
  });
}
