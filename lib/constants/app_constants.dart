/// Application-wide constants
class AppConstants {
  // Private constructor to prevent instantiation
  AppConstants._();

  /// macOS keychain access group - must match the value in
  /// macos/Runner/DebugProfile.entitlements and macos/Runner/Release.entitlements
  ///
  /// Note: In the entitlements files, this appears as:
  /// $(AppIdentifierPrefix)de.kioju.linkmanager
  ///
  /// The AppIdentifierPrefix is automatically prepended by the system at runtime,
  /// so we only specify the suffix part here. Flutter Secure Storage will
  /// automatically use the correct team identifier prefix.
  static const String macosKeychainAccessGroup = 'de.kioju.linkmanager';
}
