import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db.dart';
import '../models/link.dart';
import '../services/kioju_api.dart';
import '../utils/bookmark_import.dart';
import '../widgets/add_link_dialog.dart';
import 'link_selection_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtrl = TextEditingController();

  List<LinkItem> items = [];

  // Progress tracking state
  bool _isImporting = false;
  bool _isExporting = false;
  bool _isSyncing = false;

  // Premium status tracking
  bool? _isPremium; // null = not checked, true = premium, false = not premium
  bool _isCheckingPremium = false;

  Future<Database> get db async => AppDb.instance();

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkFirstTimeSetup();
  }

  Future<void> _checkFirstTimeSetup() async {
    // Check if API token is set
    final hasToken = await KiojuApi.hasToken();
    if (!hasToken && mounted) {
      // Show setup dialog after a short delay to ensure the UI is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showFirstTimeSetupDialog();
        }
      });
    } else if (hasToken) {
      // If we have a token, check premium status
      await _checkPremiumStatus();
    }
  }

  Future<void> _checkPremiumStatus() async {
    if (_isCheckingPremium) return;

    setState(() {
      _isCheckingPremium = true;
    });

    try {
      final response = await KiojuApi.checkPremiumStatus();
      if (mounted && response['success'] == true) {
        setState(() {
          _isPremium = response['is_premium'] == true;
        });
      }
    } catch (e) {
      // If premium check fails, assume not premium for safety
      if (mounted) {
        setState(() {
          _isPremium = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingPremium = false;
        });
      }
    }
  }

  bool get _requiresPremiumWarning => _isPremium == false;

  void _showPremiumRequiredDialog(String feature) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.diamond, color: Colors.amber),
                SizedBox(width: 12),
                Text('Premium Required'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The $feature feature requires a Kioju Premium account.'),
                const SizedBox(height: 16),
                const Text(
                  'Premium features include:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• Full access to list, search, update, and delete'),
                const Text('• Unlimited link storage'),
                const Text('• Advanced organization features'),
                const SizedBox(height: 16),
                const Text(
                  'Visit kioju.de to upgrade your account.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
                child: const Text('Settings'),
              ),
            ],
          ),
    );
  }

  void _showFirstTimeSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must set up API token
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.rocket_launch, color: Colors.blue),
                SizedBox(width: 12),
                Text('Welcome to Kioju Link Manager!'),
              ],
            ),
            content: const SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To get started, you\'ll need to configure your Kioju API token.',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '• Get your API token from your Kioju dashboard\n'
                    '• This enables syncing your bookmarks across devices\n'
                    '• Your token is stored securely on this device',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      )
                      .then((_) {
                        // Recheck setup after settings page
                        if (mounted) {
                          setState(() {});
                          _checkFirstTimeSetup();
                        }
                      });
                },
                icon: const Icon(Icons.settings),
                label: const Text('Set Up API Token'),
              ),
            ],
          ),
    );
  }

  Future<void> _refresh() async {
    final q = _searchCtrl.text.trim();
    final database = await db;
    final rows = await database.query(
      'links',
      where: q.isEmpty ? null : '(url LIKE ? OR title LIKE ? OR notes LIKE ?)',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%', '%$q%'],
      orderBy: 'updated_at DESC',
      limit: 500,
    );
    setState(() {
      items = rows.map((r) => LinkItem.fromMap(r)).toList();
    });
  }

  Future<void> _delete(int id) async {
    final database = await db;
    await database.delete('links', where: 'id=?', whereArgs: [id]);
    await _refresh();
  }

  Future<void> _import() async {
    if (_isImporting) return; // Prevent multiple simultaneous imports

    final typeGroup = XTypeGroup(
      label: 'Bookmarks',
      extensions: ['html', 'json'],
    );
    final xfile = await openFile(acceptedTypeGroups: [typeGroup]);
    if (xfile == null) return;

    setState(() {
      _isImporting = true;
    });

    try {
      _showProgressDialog('Importing', 'Reading bookmark file...');

      final path = xfile.path;
      final text = await xfile.readAsString();

      _updateProgressDialog('Parsing bookmarks...');

      List<ImportedBookmark> imported = [];
      if (path.endsWith('.html') ||
          text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
        imported = importFromNetscapeHtml(text);
      } else if (path.endsWith('.json')) {
        imported = importFromChromeJson(jsonDecode(text));
      }

      if (imported.isEmpty) {
        _hideProgressDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No links found in the selected file'),
            ),
          );
        }
        return;
      }

      _updateProgressDialog('Processing ${imported.length} links...');

      // Convert to selection items and show selection interface
      final browserLinks =
          imported
              .map((bookmark) => LinkSelectionItem.fromImported(bookmark))
              .toList();

      _updateProgressDialog('Loading existing links...');

      // Get current Kioju links for comparison
      final database = await db;
      final existingRows = await database.query('links');
      final kiojuLinks =
          existingRows
              .map((r) => LinkSelectionItem.fromKioju(LinkItem.fromMap(r)))
              .toList();

      _hideProgressDialog();

      // Show selection dialog
      if (mounted) {
        await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder:
                (_) => LinkSelectionPage(
                  initialBrowserLinks: browserLinks,
                  initialKiojuLinks: kiojuLinks,
                ),
          ),
        );

        // Always refresh when returning from link selection
        await _refresh();
      }
    } catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _export() async {
    if (_isExporting) return; // Prevent multiple simultaneous exports

    setState(() {
      _isExporting = true;
    });

    try {
      _showProgressDialog('Exporting', 'Loading links...');

      final database = await db;
      final rows = await database.query('links');
      final kiojuLinks =
          rows
              .map((r) => LinkSelectionItem.fromKioju(LinkItem.fromMap(r)))
              .toList();

      _hideProgressDialog();

      if (kiojuLinks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No links to export')));
        }
        return;
      }

      // Show selection dialog
      if (mounted) {
        await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) => LinkSelectionPage(initialKiojuLinks: kiojuLinks),
          ),
        );

        // Always refresh when returning from link selection
        await _refresh();
      }
    } catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _pull() async {
    if (_isSyncing) return; // Prevent multiple simultaneous syncs

    // Check premium status for list operation
    if (_requiresPremiumWarning) {
      _showPremiumRequiredDialog('Sync Down (List)');
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      // Check rate limit status before making the request
      final rateLimitStatus = KiojuApi.getRateLimitStatus();
      if (!rateLimitStatus['canMakeRequest']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rateLimitStatus['message']),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      _showProgressDialog('Syncing Down', 'Downloading links from Kioju...');

      // Fetch all links with pagination
      List<Map<String, dynamic>> allRemoteLinks = [];
      int offset = 0;
      const int batchSize = 100; // API max limit

      while (true) {
        _updateProgressDialog(
          'Downloading batch ${(offset / batchSize + 1).toInt()}...',
        );

        final batch = await KiojuApi.listLinks(
          limit: batchSize,
          offset: offset,
        );
        if (batch.isEmpty) break; // No more links

        allRemoteLinks.addAll(batch);
        offset += batchSize;

        // If we got less than the batch size, we've reached the end
        if (batch.length < batchSize) break;
      }

      final remote = allRemoteLinks;

      _updateProgressDialog('Processing ${remote.length} links...');

      final database = await db;
      final batch = database.batch();

      int processed = 0;
      for (final m in remote) {
        final url = (m['url'] ?? m['link'] ?? '') as String;
        if (url.isEmpty) continue;
        final title = (m['title'] ?? '') as String?;
        final description = (m['description'] ?? '') as String?;
        final isPrivate = m['is_private'];

        // Improved tag parsing - extract slugs from tag objects
        final tags = _parseTagsFromApi(m['tags']);

        final id = (m['id'] ?? m['remote_id'] ?? '').toString();
        batch.insert('links', {
          'url': url,
          'title': (title?.isNotEmpty ?? false) ? title : null,
          'notes': (description?.isNotEmpty ?? false) ? description : null,
          'tags': tags,
          'is_private':
              (isPrivate is bool
                      ? isPrivate
                      : (isPrivate == 1 || isPrivate == '1'))
                  ? 1
                  : 0,
          'remote_id': id.isNotEmpty ? id : null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.rawUpdate(
          'UPDATE links SET title=COALESCE(?, title), notes=COALESCE(?, notes), tags=COALESCE(?, tags), is_private=COALESCE(?, is_private), updated_at=CURRENT_TIMESTAMP WHERE remote_id=?',
          [
            title,
            description,
            tags,
            (isPrivate is bool
                    ? isPrivate
                    : (isPrivate == 1 || isPrivate == '1'))
                ? 1
                : 0,
            id,
          ],
        );

        processed++;
        if (processed % 10 == 0) {
          _updateProgressDialog(
            'Processing $processed/${remote.length} links...',
          );
        }
      }

      _updateProgressDialog('Saving to database...');
      await batch.commit(noResult: true);

      _hideProgressDialog();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pulled ${remote.length} links')),
        );
      }
      await _refresh();
    } on RateLimitException catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.orange,
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } on AuthenticationException catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
          ),
        );
      }
    } on AuthorizationException catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
          ),
        );
      }
    } catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pull failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  /// Parse tags from Kioju API response
  /// Expects tags to be an array of objects with 'slug' field
  String _parseTagsFromApi(dynamic tagsRaw) {
    if (tagsRaw == null) return '';

    if (tagsRaw is List) {
      final tagSlugs = <String>[];
      for (final tagItem in tagsRaw) {
        if (tagItem is Map<String, dynamic>) {
          // Priority 1: Extract slug from tag object (Kioju format)
          final slug = tagItem['slug']?.toString();
          if (slug?.isNotEmpty == true) {
            tagSlugs.add(slug!);
            continue;
          }

          // Priority 2: Try 'name' field as fallback
          final name = tagItem['name']?.toString();
          if (name?.isNotEmpty == true) {
            tagSlugs.add(name!);
            continue;
          }

          // Priority 3: Try 'title' field as fallback
          final title = tagItem['title']?.toString();
          if (title?.isNotEmpty == true) {
            tagSlugs.add(title!);
            continue;
          }
        } else if (tagItem is String && tagItem.isNotEmpty) {
          // Handle simple string tags as fallback
          tagSlugs.add(tagItem);
        }
      }
      return tagSlugs.join(',');
    } else if (tagsRaw is String) {
      return tagsRaw;
    }

    return '';
  }

  Future<void> _push() async {
    if (_isSyncing) return; // Prevent multiple simultaneous syncs

    setState(() {
      _isSyncing = true;
    });

    try {
      // Check rate limit status before making requests
      final rateLimitStatus = KiojuApi.getRateLimitStatus();
      if (!rateLimitStatus['canMakeRequest']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rateLimitStatus['message']),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final database = await db;
      final rows = await database.query('links', where: 'remote_id IS NULL');

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No new links to upload')),
          );
        }
        return;
      }

      _showProgressDialog(
        'Syncing Up',
        'Uploading ${rows.length} links to Kioju...',
      );

      int ok = 0;
      int failed = 0;
      String? lastError;

      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        _updateProgressDialog('Uploading ${i + 1}/${rows.length} links...');

        try {
          final isPrivate = (r['is_private'] as int? ?? 0) == 1;
          final res = await KiojuApi.addLink(
            url: r['url'] as String,
            title: r['title'] as String?,
            tags:
                (r['tags'] as String? ?? '')
                    .split(',')
                    .where((e) => e.isNotEmpty)
                    .toList(),
            isPrivate: isPrivate ? '1' : '0',
          );

          // Check if the response indicates success
          if (res['success'] == true) {
            final id =
                (res['link_id'] ?? res['id'] ?? res['remote_id'] ?? '')
                    .toString();
            if (id.isNotEmpty) {
              await database.update(
                'links',
                {
                  'remote_id': id,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                where: 'id=?',
                whereArgs: [r['id']],
              );
              ok++;
            } else {
              // API returned success but no ID - this is unusual but not necessarily an error
              ok++;
            }
          } else {
            // API returned success=false
            failed++;
            lastError = res['message']?.toString() ?? 'Unknown API error';
          }
        } on RateLimitException catch (e) {
          // Stop processing if rate limited
          lastError = e.message;
          break;
        } on AuthenticationException catch (e) {
          lastError = e.message;
          break;
        } on AuthorizationException catch (e) {
          lastError = e.message;
          break;
        } catch (e) {
          failed++;
          lastError = e.toString();
          // Continue processing other links
        }
      }

      _hideProgressDialog();

      if (mounted) {
        if (lastError != null &&
            (lastError.contains('Rate limited') ||
                lastError.contains('Invalid') ||
                lastError.contains('forbidden') ||
                lastError.contains('Authentication') ||
                lastError.contains('Authorization'))) {
          // Show specific error for auth/rate limit issues only
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lastError),
              duration: const Duration(seconds: 8),
              backgroundColor:
                  lastError.contains('Rate limited')
                      ? Colors.orange
                      : Colors.red,
              action:
                  lastError.contains('Rate limited')
                      ? null
                      : SnackBarAction(
                        label: 'Settings',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsPage(),
                            ),
                          );
                        },
                      ),
            ),
          );
        } else if (ok > 0 || failed == 0) {
          // Show success message if any uploads succeeded or no failures
          String message = 'Pushed $ok links successfully';
          if (failed > 0) {
            message += ' ($failed failed)';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: failed > 0 ? Colors.orange : Colors.green,
            ),
          );
        } else if (failed > 0 && ok == 0) {
          // Only show error if everything failed and we have a specific error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lastError ?? 'Upload failed: Unknown error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

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
                Icons.bookmark_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Kioju Link Manager',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            if (_isPremium == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond, size: 12, color: Colors.black87),
                    const SizedBox(width: 4),
                    Text(
                      'Premium',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              )
            else if (_isPremium == false)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Free',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          if (!isMobile) ..._buildDesktopActions(),
          if (isMobile)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: _handleMenuAction,
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(
                      value: 'add',
                      child: Row(
                        children: [
                          Icon(Icons.add),
                          SizedBox(width: 8),
                          Text('Add Link'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file),
                          SizedBox(width: 8),
                          Text('Import'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.download),
                          SizedBox(width: 8),
                          Text('Export'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'pull',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_download),
                          SizedBox(width: 8),
                          Text('Sync Down'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'push',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload),
                          SizedBox(width: 8),
                          Text('Sync Up'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings),
                          SizedBox(width: 8),
                          Text('Settings'),
                        ],
                      ),
                    ),
                  ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Section
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                hintText: 'Search links...',
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              onChanged: (_) => _refresh(),
            ),
          ),

          // Links List Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Your Links',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Links List
          Expanded(
            child:
                items.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _buildLinkCard(items[i], i),
                    ),
          ),
        ],
      ),
      floatingActionButton:
          isMobile
              ? FloatingActionButton(
                onPressed:
                    (_isImporting || _isExporting || _isSyncing)
                        ? null
                        : _showAddLinkDialog,
                child: const Icon(Icons.add),
              )
              : null,
    );
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
      }
    }
  }

  // Helper methods for building UI components
  List<Widget> _buildDesktopActions() {
    final bool isAnyOperationRunning =
        _isImporting || _isExporting || _isSyncing;

    return [
      IconButton(
        onPressed: isAnyOperationRunning ? null : _showAddLinkDialog,
        icon: const Icon(Icons.add),
        tooltip: 'Add Link',
      ),
      IconButton(
        onPressed: (_isImporting || isAnyOperationRunning) ? null : _import,
        icon:
            _isImporting
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.upload_file),
        tooltip: _isImporting ? 'Importing...' : 'Import',
      ),
      IconButton(
        onPressed: (_isExporting || isAnyOperationRunning) ? null : _export,
        icon:
            _isExporting
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.download),
        tooltip: _isExporting ? 'Exporting...' : 'Export',
      ),
      IconButton(
        onPressed: (_isSyncing || isAnyOperationRunning) ? null : _pull,
        icon:
            _isSyncing
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.cloud_download),
        tooltip: _isSyncing ? 'Syncing...' : 'Sync Down',
      ),
      IconButton(
        onPressed: (_isSyncing || isAnyOperationRunning) ? null : _push,
        icon:
            _isSyncing
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.cloud_upload),
        tooltip: _isSyncing ? 'Syncing...' : 'Sync Up',
      ),
      IconButton(
        onPressed:
            isAnyOperationRunning
                ? null
                : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                  if (mounted) setState(() {});
                },
        icon: const Icon(Icons.settings),
        tooltip: 'Settings',
      ),
    ];
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'add':
        _showAddLinkDialog();
        break;
      case 'import':
        _import();
        break;
      case 'export':
        _export();
        break;
      case 'pull':
        _pull();
        break;
      case 'push':
        _push();
        break;
      case 'settings':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SettingsPage()))
            .then((_) {
              // Check if token was set and refresh UI
              if (mounted) {
                setState(() {});
                _checkFirstTimeSetup();
              }
            });
        break;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No links yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first link to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed:
                (_isImporting || _isExporting || _isSyncing)
                    ? null
                    : _showAddLinkDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Link'),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkCard(LinkItem item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openUrl(item.url),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.link,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        if (item.isPrivate) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.lock,
                            size: 12,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title?.isNotEmpty == true
                              ? item.title!
                              : 'Untitled Link',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.url,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.notes?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.notes!,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditLinkDialog(item);
                      } else if (value == 'delete') {
                        _showDeleteConfirmation(item.id!);
                      } else if (value == 'copy') {
                        _copyToClipboard(item.url);
                      }
                    },
                    itemBuilder:
                        (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'copy',
                            child: Row(
                              children: [
                                Icon(Icons.copy),
                                SizedBox(width: 8),
                                Text('Copy URL'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete'),
                              ],
                            ),
                          ),
                        ],
                    child: Icon(
                      Icons.more_vert,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (item.tags.isNotEmpty ||
                  item.collection?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ...item.tags.map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    if (item.collection?.isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder,
                              size: 12,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.collection!,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAddLinkDialog() async {
    final result = await showAddLinkDialog(context);
    if (result != null) {
      final database = await db;

      // Check if URL already exists (case-insensitive duplicate detection)
      // We preserve original URL case but check for duplicates ignoring case
      final inputUrl = result['url'] as String;

      // Get all existing URLs and check for case-insensitive matches
      final allExistingLinks = await database.query('links');
      final matchingLinks =
          allExistingLinks.where((link) {
            final existingUrl = link['url'] as String;

            // Simple case-insensitive comparison for exact matches
            if (existingUrl.toLowerCase() == inputUrl.toLowerCase()) {
              return true;
            }

            // Check for common URL variations (www, trailing slash, protocol)
            // but preserve case in actual comparison
            try {
              final existingUri = Uri.parse(existingUrl);
              final inputUri = Uri.parse(inputUrl);

              // Compare normalized versions (case-insensitive)
              final existingNormalized =
                  Uri(
                    scheme: existingUri.scheme.toLowerCase(),
                    host: existingUri.host.toLowerCase().replaceAll(
                      RegExp(r'^www\.'),
                      '',
                    ),
                    port: existingUri.hasPort ? existingUri.port : null,
                    path:
                        existingUri.path.endsWith('/') &&
                                existingUri.path.length > 1
                            ? existingUri.path.substring(
                              0,
                              existingUri.path.length - 1,
                            )
                            : existingUri.path,
                    query:
                        existingUri.query.isNotEmpty ? existingUri.query : null,
                  ).toString().toLowerCase();

              final inputNormalized =
                  Uri(
                    scheme: inputUri.scheme.toLowerCase(),
                    host: inputUri.host.toLowerCase().replaceAll(
                      RegExp(r'^www\.'),
                      '',
                    ),
                    port: inputUri.hasPort ? inputUri.port : null,
                    path:
                        inputUri.path.endsWith('/') && inputUri.path.length > 1
                            ? inputUri.path.substring(
                              0,
                              inputUri.path.length - 1,
                            )
                            : inputUri.path,
                    query: inputUri.query.isNotEmpty ? inputUri.query : null,
                  ).toString().toLowerCase();

              return existingNormalized == inputNormalized;
            } catch (e) {
              // If URI parsing fails, fall back to simple comparison
              return false;
            }
          }).toList();

      if (matchingLinks.isNotEmpty && mounted) {
        // URL already exists, show options to user
        final existingLink = matchingLinks.first;
        final shouldUpdate = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    const Text('Duplicate Link Found'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('This URL already exists in your collection:'),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.link,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Existing Link',
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            existingLink['title'] as String? ?? 'No title',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            existingLink['url'] as String,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (existingLink['notes'] != null &&
                              (existingLink['notes'] as String).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              existingLink['notes'] as String,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Added: ${_formatDate(existingLink['created_at'] as String?)}',
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
                    const SizedBox(height: 16),
                    const Text(
                      'Would you like to update the existing link with the new information?',
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep Original'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Update Link'),
                  ),
                ],
              ),
        );

        if (shouldUpdate == true) {
          // Update existing link
          await database.update(
            'links',
            {
              'title': result['title'],
              'tags': (result['tags'] as List<String>).join(','),
              'notes':
                  result['description'], // Store description in notes field
              'is_private': result['isPrivate'] == true ? 1 : 0,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [existingLink['id']],
          );

          await _refresh();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Link updated successfully')),
            );
          }
        }
        // If shouldUpdate is false or null, do nothing (keep original)
      } else {
        // URL doesn't exist, add new link
        try {
          await database.insert('links', {
            'url': result['url'],
            'title': result['title'],
            'tags': (result['tags'] as List<String>).join(','),
            'notes': result['description'], // Store description in notes field
            'is_private':
                result['isPrivate'] == true ? 1 : 0, // Store privacy setting
          });

          await _refresh();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Link added successfully')),
            );
          }
        } catch (e) {
          // Handle database constraint violations
          if (mounted) {
            String errorMessage = 'Failed to add link';
            if (e.toString().contains('UNIQUE constraint failed')) {
              errorMessage = 'This URL already exists in your collection';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    }
  }

  void _showEditLinkDialog(LinkItem item) async {
    // Check premium status for update operation
    if (_requiresPremiumWarning) {
      _showPremiumRequiredDialog('Edit Link (Update)');
      return;
    }

    final result = await showEditLinkDialog(context, item);
    if (result != null) {
      try {
        final database = await db;

        // Update local database first
        await database.update(
          'links',
          {
            'title': result['title'],
            'tags': (result['tags'] as List<String>).join(','),
            'notes': result['description'], // Store description in notes field
            'is_private': result['isPrivate'] == true ? 1 : 0,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );

        // If the item has a remote_id, try to update it on the server
        if (item.remoteId != null && item.remoteId!.isNotEmpty) {
          try {
            await KiojuApi.updateLink(
              id: item.remoteId!,
              title: result['title'],
              description: result['description'],
              isPrivate: result['isPrivate'] == true ? '1' : '0',
              tags: result['tags'] as List<String>,
            );
          } catch (e) {
            // If server update fails, show warning but keep local changes
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Link updated locally, but server update failed: ${e.toString()}',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        }

        await _refresh();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update link: ${e.toString()}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _showDeleteConfirmation(int id) {
    // Check premium status for delete operation
    if (_requiresPremiumWarning) {
      _showPremiumRequiredDialog('Delete Link');
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Link'),
            content: const Text('Are you sure you want to delete this link?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _delete(id);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  void _copyToClipboard(String text) {
    // Note: You might want to add clipboard package for this functionality
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('URL copied: $text')));
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return 'Unknown';
    }

    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
      } else if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return months == 1 ? '1 month ago' : '$months months ago';
      } else {
        final years = (difference.inDays / 365).floor();
        return years == 1 ? '1 year ago' : '$years years ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  // Progress dialog helper methods
  void _showProgressDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(title),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ),
          ),
    );
  }

  void _updateProgressDialog(String message) {
    // For basic implementation, we'll just let the existing dialog show
    // A more sophisticated implementation could use a ValueNotifier or StateBuilder
    // to update the dialog content dynamically
  }

  void _hideProgressDialog() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }
}
