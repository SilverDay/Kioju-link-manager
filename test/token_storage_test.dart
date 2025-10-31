import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kioju_link_manager/services/kioju_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  String? _path;
  
  @override
  Future<String?> getApplicationSupportPath() async {
    _path ??= await Directory.systemTemp.createTemp('kioju_test').then((dir) => dir.path);
    return _path;
  }
}

void main() {
  // Initialize FFI for testing
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  group('API Token Storage Fallback', () {
    // Clean up after each test by clearing the token
    tearDown(() async {
      try {
        await KiojuApi.setToken(null);
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('setToken should validate and store token', () async {
      // This test ensures that the token can be set
      // In a real environment, it would use either secure storage or database
      final testToken = 'test_token_1234567890abcdef';
      
      await KiojuApi.setToken(testToken);
      
      // Verify the token was stored
      final hasToken = await KiojuApi.hasToken();
      expect(hasToken, true);
    });

    test('setToken should reject invalid tokens', () async {
      // Test with a token that's too short
      expect(
        () async => await KiojuApi.setToken('short'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setToken with null should clear token', () async {
      // First set a token
      await KiojuApi.setToken('test_token_1234567890abcdef');
      expect(await KiojuApi.hasToken(), true);
      
      // Then clear it
      await KiojuApi.setToken(null);
      expect(await KiojuApi.hasToken(), false);
    });

    test('setToken with empty string should clear token', () async {
      // First set a token
      await KiojuApi.setToken('test_token_1234567890abcdef');
      expect(await KiojuApi.hasToken(), true);
      
      // Then clear it with empty string
      await KiojuApi.setToken('');
      expect(await KiojuApi.hasToken(), false);
    });
  });
}
