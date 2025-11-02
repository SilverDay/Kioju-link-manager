// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kioju_link_manager/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Set a larger screen size to prevent overflow issues
    await tester.binding.setSurfaceSize(const Size(1200, 800));

    // Build our app and trigger a frame.
    await tester.pumpWidget(const KiojuApp());

    // Wait for the app to settle
    await tester.pumpAndSettle();

    // Verify that the app starts properly
    expect(find.text('Kioju Link Manager'), findsOneWidget);
  });
}
