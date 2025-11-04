/// Application-wide constants
class AppConstants {
  // Private constructor to prevent instantiation
  AppConstants._();

  /// macOS keychain access group - must match the value in
  /// macos/Runner/DebugProfile.entitlements and macos/Runner/Release.entitlements
  static const String macosKeychainAccessGroup = 'de.kioju.linkmanager';
}
