import 'dart:async';
import 'package:flutter/material.dart';
import 'kioju_api.dart';

/// Service for managing premium status checking and notifications
class PremiumStatusService {
  static PremiumStatusService? _instance;
  static PremiumStatusService get instance => _instance ??= PremiumStatusService._();
  
  PremiumStatusService._();

  // Premium status state
  bool _isPremium = false;
  DateTime? _lastChecked;
  String? _premiumMessage;
  bool _isChecking = false;
  
  // Cache duration for premium status (24 hours)
  static const Duration _cacheDuration = Duration(hours: 24);
  
  // Notification callbacks
  final List<VoidCallback> _statusChangeListeners = [];
  
  /// Current premium status
  bool get isPremium => _isPremium;
  
  /// Last time premium status was checked
  DateTime? get lastChecked => _lastChecked;
  
  /// Premium status message from API
  String? get premiumMessage => _premiumMessage;
  
  /// Whether a premium check is currently in progress
  bool get isChecking => _isChecking;
  
  /// Add a listener for premium status changes
  void addStatusChangeListener(VoidCallback listener) {
    _statusChangeListeners.add(listener);
  }
  
  /// Remove a listener for premium status changes
  void removeStatusChangeListener(VoidCallback listener) {
    _statusChangeListeners.remove(listener);
  }
  
  /// Notify all listeners of status changes
  void _notifyListeners() {
    for (final listener in _statusChangeListeners) {
      try {
        listener();
      } catch (e) {
        // Ignore listener errors to prevent cascade failures
      }
    }
  }
  
  /// Check if premium status cache is still valid
  bool get _isCacheValid {
    if (_lastChecked == null) return false;
    return DateTime.now().difference(_lastChecked!) < _cacheDuration;
  }
  
  /// Check premium status from API
  Future<bool> checkPremiumStatus({bool forceRefresh = false}) async {
    // Return cached result if valid and not forcing refresh
    if (!forceRefresh && _isCacheValid) {
      return _isPremium;
    }
    
    // Prevent concurrent checks
    if (_isChecking) {
      return _isPremium;
    }
    
    _isChecking = true;
    
    try {
      final response = await KiojuApi.checkPremiumStatus();
      

      
      final wasPremium = _isPremium;
      _isPremium = response['is_premium'] == true;
      _premiumMessage = response['message'] as String?;
      _lastChecked = DateTime.now();
      

      
      // Notify listeners if status changed
      if (wasPremium != _isPremium) {
        _notifyListeners();
      }
      
      return _isPremium;
      
    } catch (e) {
      // On error, keep existing status but mark as stale
      _lastChecked = null;
      
      if (e is AuthenticationException) {
        _isPremium = false;
        _premiumMessage = 'Please check your API token in Settings';
      } else if (e is AuthorizationException) {
        _isPremium = false;
        _premiumMessage = 'API token does not have premium access';
      } else {
        _premiumMessage = 'Unable to verify premium status. Some features may be limited.';
      }
      
      _notifyListeners();
      rethrow;
    } finally {
      _isChecking = false;
    }
  }
  
  /// Check if a specific feature requires premium access
  bool isPremiumRequired(String feature) {
    switch (feature.toLowerCase()) {
      case 'collections':
      case 'collection_management':
      case 'folders':
        return true;
      default:
        return false;
    }
  }
  
  /// Show premium notification based on current status
  void showPremiumNotification(BuildContext context, {String? feature}) {
    if (_isPremium) {
      // No notification needed for premium users
      return;
    }
    
    String message;
    if (feature != null && isPremiumRequired(feature)) {
      message = _getPremiumRequiredMessage(feature);
    } else {
      message = _premiumMessage ?? 'Premium status unknown';
    }
    
    _showNotificationSnackBar(context, message);
  }
  
  /// Get premium required message for specific feature
  String _getPremiumRequiredMessage(String feature) {
    switch (feature.toLowerCase()) {
      case 'collections':
      case 'collection_management':
      case 'folders':
        return 'Collection management requires Kioju Premium. Upgrade to organize your links into folders and access advanced features.';
      default:
        return 'This feature requires Kioju Premium. Upgrade to access advanced functionality.';
    }
  }
  
  /// Show notification snack bar
  void _showNotificationSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: _isPremium ? null : SnackBarAction(
          label: 'Upgrade',
          onPressed: () => handlePremiumUpgrade(context),
        ),
      ),
    );
  }
  
  /// Handle premium upgrade process
  void handlePremiumUpgrade(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upgrade to Premium'),
        content: const Text(
          'To access premium features like collection management, please upgrade your Kioju account.\n\n'
          'Visit kioju.de to upgrade your account, then restart the app to refresh your premium status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Force refresh premium status after user potentially upgrades
              checkPremiumStatus(forceRefresh: true);
            },
            child: const Text('I Upgraded'),
          ),
        ],
      ),
    );
  }
  
  /// Reset premium status (useful for testing or token changes)
  void reset() {
    _isPremium = false;
    _lastChecked = null;
    _premiumMessage = null;
    _isChecking = false;
    _notifyListeners();
  }
  
  /// Get premium status summary for debugging
  Map<String, dynamic> getStatusSummary() {
    return {
      'isPremium': _isPremium,
      'lastChecked': _lastChecked?.toIso8601String(),
      'message': _premiumMessage,
      'isChecking': _isChecking,
      'cacheValid': _isCacheValid,
    };
  }
}
