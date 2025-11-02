import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/kioju_api.dart';
import '../services/app_settings.dart';
import '../services/sync_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tokenCtrl = TextEditingController();
  bool _hasToken = false;
  bool _autoFetchMetadata = true;
  bool _immediateSyncEnabled = false;
  bool _isPremium = false;
  bool _isCheckingPremium = false;
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _hasToken = await KiojuApi.hasToken();
    _autoFetchMetadata = await AppSettings.getAutoFetchMetadata();
    _immediateSyncEnabled = await SyncSettings.isImmediateSyncEnabled();

    // Load app version
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    // Check premium status if we have a token
    if (_hasToken) {
      await _checkPremiumStatus();
    }

    setState(() {});
  }

  Future<void> _checkPremiumStatus() async {
    if (_isCheckingPremium) return;

    setState(() {
      _isCheckingPremium = true;
    });

    try {
      final response = await KiojuApi.checkPremiumStatus();
      if (response['success'] == true) {
        setState(() {
          _isPremium = response['is_premium'] ?? false;
        });
      }
    } catch (e) {
      // Ignore errors, just assume not premium
      setState(() {
        _isPremium = false;
      });
    } finally {
      setState(() {
        _isCheckingPremium = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.settings,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Preferences Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.tune,
                          color:
                              Theme.of(context).colorScheme.onTertiaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'App Preferences',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Auto-fetch metadata setting
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto-fetch Title & Description',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Automatically retrieve page title and description when adding links',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _autoFetchMetadata,
                          onChanged: (value) async {
                            final scaffoldMessenger = ScaffoldMessenger.of(
                              context,
                            );

                            setState(() {
                              _autoFetchMetadata = value;
                            });

                            await AppSettings.setAutoFetchMetadata(value);

                            if (mounted) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? 'Auto-fetch enabled'
                                        : 'Auto-fetch disabled',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Immediate sync setting
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sync,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Immediate Sync',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _immediateSyncEnabled
                                    ? 'Changes are synced to server immediately'
                                    : 'Changes are saved locally and synced manually',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _immediateSyncEnabled,
                          onChanged: (value) async {
                            final scaffoldMessenger = ScaffoldMessenger.of(
                              context,
                            );
                            final primaryColor = Theme.of(context).colorScheme.primary;
                            final errorColor = Theme.of(context).colorScheme.error;

                            try {
                              setState(() {
                                _immediateSyncEnabled = value;
                              });

                              await SyncSettings.setImmediateSyncEnabled(value);

                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          value
                                              ? 'Immediate sync enabled'
                                              : 'Manual sync enabled',
                                        ),
                                      ],
                                    ),
                                    backgroundColor: primaryColor,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              // Revert the UI state on error
                              setState(() {
                                _immediateSyncEnabled = !value;
                              });

                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(
                                          Icons.error,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Failed to save sync preference: ${e.toString()}',
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: errorColor,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // API Configuration Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.key,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'API Configuration',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your Kioju API token to sync your bookmarks',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // API Token
                  TextField(
                    controller: _tokenCtrl,
                    decoration: InputDecoration(
                      labelText: 'API Token',
                      prefixIcon: const Icon(Icons.key),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      helperText: 'Your secure API authentication token',
                      suffixIcon:
                          _hasToken
                              ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                              : null,
                    ),
                    obscureText: true,
                  ),

                  if (_hasToken) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Token is securely stored',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            _isPremium
                                ? Theme.of(
                                  context,
                                ).colorScheme.tertiaryContainer
                                : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isPremium ? Icons.diamond : Icons.info_outline,
                            color:
                                _isPremium
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.onTertiaryContainer
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isCheckingPremium
                                  ? 'Checking premium status...'
                                  : _isPremium
                                  ? 'Premium account - All features available'
                                  : 'Free account - Some features require premium',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color:
                                    _isPremium
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.onTertiaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (_isCheckingPremium)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final t = _tokenCtrl.text.trim();
                        final primaryColor =
                            Theme.of(context).colorScheme.primary;
                        final errorColor = Theme.of(context).colorScheme.error;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);

                        try {
                          await KiojuApi.setToken(t.isEmpty ? null : t);

                          if (mounted) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.check, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('API token saved successfully'),
                                  ],
                                ),
                                backgroundColor: primaryColor,
                              ),
                            );
                          }
                          await _init(); // This will refresh premium status
                        } catch (e) {
                          if (mounted) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.error,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Failed to save API token: ${e.toString()}',
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: errorColor,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Save API Token'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Help Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Help & Information',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _buildClickableHelpItem(
                    context,
                    Icons.info_outline,
                    'About Kioju',
                    'Visit the Kioju website to learn more',
                    'https://kioju.de',
                  ),
                  const SizedBox(height: 16),
                  
                  // Top Menu Buttons Explanation
                  Text(
                    'Top Menu Buttons',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildHelpItem(
                    context,
                    Icons.add_link,
                    'New Link',
                    'Add a new bookmark to your collection',
                  ),
                  const SizedBox(height: 8),
                  _buildHelpItem(
                    context,
                    Icons.create_new_folder,
                    'New Collection',
                    'Create a new collection to organize your links',
                  ),
                  const SizedBox(height: 8),
                  _buildHelpItem(
                    context,
                    Icons.cloud_download,
                    'Sync Down',
                    'Download your links from the Kioju server',
                  ),
                  const SizedBox(height: 8),
                  _buildHelpItem(
                    context,
                    Icons.cloud_upload,
                    'Sync Up',
                    'Upload your local changes to the Kioju server',
                  ),
                  const SizedBox(height: 8),
                  _buildHelpItem(
                    context,
                    Icons.file_download,
                    'Import from Browser',
                    'Import bookmarks from your browser\'s bookmark file',
                  ),
                  const SizedBox(height: 8),
                  _buildHelpItem(
                    context,
                    Icons.file_upload,
                    'Export to Browser',
                    'Export your links to a browser-compatible bookmark file',
                  ),
                  const SizedBox(height: 24),

                  // Divider
                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),

                  const SizedBox(height: 16),

                  // App Information
                  _buildHelpItem(context, Icons.info, 'Version', _appVersion),
                  const SizedBox(height: 12),
                  _buildHelpItem(
                    context,
                    Icons.gavel,
                    'License',
                    'MIT License - Open Source Software',
                  ),
                  const SizedBox(height: 12),
                  _buildHelpItem(
                    context,
                    Icons.code,
                    'Created by',
                    'SilverDay',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClickableHelpItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    String url,
  ) {
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $urlString'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening link: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
