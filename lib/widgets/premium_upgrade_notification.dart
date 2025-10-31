import 'package:flutter/material.dart';
import '../services/premium_status_service.dart';

/// Widget that displays premium upgrade notifications
class PremiumUpgradeNotification extends StatefulWidget {
  final String? feature;
  final Widget child;
  
  const PremiumUpgradeNotification({
    super.key,
    this.feature,
    required this.child,
  });
  
  @override
  State<PremiumUpgradeNotification> createState() => _PremiumUpgradeNotificationState();
}

class _PremiumUpgradeNotificationState extends State<PremiumUpgradeNotification> {
  bool _isPremium = false;
  bool _hasShownNotification = false;
  
  @override
  void initState() {
    super.initState();
    _isPremium = PremiumStatusService.instance.isPremium;
    
    // Listen for premium status changes
    PremiumStatusService.instance.addStatusChangeListener(_onPremiumStatusChanged);
    
    // Show notification if feature requires premium and user is not premium
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowNotification();
    });
  }
  
  @override
  void dispose() {
    PremiumStatusService.instance.removeStatusChangeListener(_onPremiumStatusChanged);
    super.dispose();
  }
  
  void _onPremiumStatusChanged() {
    if (mounted) {
      setState(() {
        _isPremium = PremiumStatusService.instance.isPremium;
      });
    }
  }
  
  void _checkAndShowNotification() {
    if (!_hasShownNotification && 
        widget.feature != null && 
        PremiumStatusService.instance.isPremiumRequired(widget.feature!) && 
        !_isPremium) {
      
      _hasShownNotification = true;
      PremiumStatusService.instance.showPremiumNotification(context, feature: widget.feature);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Banner widget that shows premium status
class PremiumStatusBanner extends StatefulWidget {
  const PremiumStatusBanner({super.key});
  
  @override
  State<PremiumStatusBanner> createState() => _PremiumStatusBannerState();
}

class _PremiumStatusBannerState extends State<PremiumStatusBanner> {
  bool _isPremium = false;
  bool _isVisible = false;
  
  @override
  void initState() {
    super.initState();
    _isPremium = PremiumStatusService.instance.isPremium;
    _isVisible = !_isPremium;
    
    // Listen for premium status changes
    PremiumStatusService.instance.addStatusChangeListener(_onPremiumStatusChanged);
  }
  
  @override
  void dispose() {
    PremiumStatusService.instance.removeStatusChangeListener(_onPremiumStatusChanged);
    super.dispose();
  }
  
  void _onPremiumStatusChanged() {
    if (mounted) {
      setState(() {
        _isPremium = PremiumStatusService.instance.isPremium;
        _isVisible = !_isPremium;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Some features require Kioju Premium',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => PremiumStatusService.instance.handlePremiumUpgrade(context),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}

/// Mixin for widgets that need premium feature gating
mixin PremiumFeatureMixin<T extends StatefulWidget> on State<T> {
  bool get isPremium => PremiumStatusService.instance.isPremium;
  
  bool isPremiumRequired(String feature) {
    return PremiumStatusService.instance.isPremiumRequired(feature);
  }
  
  void showPremiumRequiredDialog(String feature) {
    PremiumStatusService.instance.showPremiumNotification(context, feature: feature);
  }
  
  bool checkPremiumAccess(String feature) {
    if (isPremiumRequired(feature) && !isPremium) {
      showPremiumRequiredDialog(feature);
      return false;
    }
    return true;
  }
}
