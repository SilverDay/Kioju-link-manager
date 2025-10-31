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

    testWidgets('should display immediate sync toggle in settings', (WidgetTester tester) async {
      // Build the settings page with a larger screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(
        MaterialApp(
          home: const SettingsPage(),
        ),
      );

      // Wait for the page to load
      await tester.pumpAndSettle();

      // Find the immediate sync toggle
      expect(find.text('Immediate Sync'), findsOneWidget);
      expect(find.byType(Switch), findsAtLeast(1));
    });

    testWidgets('should show default state for immediate sync toggle', (WidgetTester tester) async {
      // Build the settings page with a larger screen size (default state should be manual sync)
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(
        MaterialApp(
          home: const SettingsPage(),
        ),
      );

      // Wait for the page to load
      await tester.pumpAndSettle();

      // Find the immediate sync section
      expect(find.text('Immediate Sync'), findsOneWidget);
      expect(find.textContaining('Changes are saved locally'), findsOneWidget);
    });

    testWidgets('should display sync preference descriptions', (WidgetTester tester) async {
      // Build the settings page with a larger screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(
        MaterialApp(
          home: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Should show manual sync description by default
      expect(find.textContaining('Changes are saved locally'), findsOneWidget);
    });

    testWidgets('should have accessible labels for sync toggle', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(
        MaterialApp(
          home: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify accessibility
      expect(find.text('Immediate Sync'), findsOneWidget);
      
      // The switch should be part of a semantically meaningful group
      final switches = find.byType(Switch);
      expect(switches, findsAtLeast(1));
      
      // Verify descriptive text is present
      expect(find.textContaining('Changes are'), findsOneWidget);
    });

    testWidgets('should show sync settings section', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(
        MaterialApp(
          home: const SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the sync settings are present
      expect(find.text('Immediate Sync'), findsOneWidget);
      expect(find.text('App Preferences'), findsOneWidget);
    });
  });
}
