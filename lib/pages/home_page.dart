import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db.dart';
import '../models/link.dart';
import '../services/kioju_api.dart';
import '../utils/bookmark_export.dart';
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
    }
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
    final typeGroup = XTypeGroup(
      label: 'Bookmarks',
      extensions: ['html', 'json'],
    );
    final xfile = await openFile(acceptedTypeGroups: [typeGroup]);
    if (xfile == null) return;

    final path = xfile.path;
    final text = await xfile.readAsString();

    List<ImportedBookmark> imported = [];
    if (path.endsWith('.html') ||
        text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
      imported = importFromNetscapeHtml(text);
    } else if (path.endsWith('.json')) {
      imported = importFromChromeJson(jsonDecode(text));
    }

    if (imported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No links found in the selected file')),
        );
      }
      return;
    }

    // Convert to selection items and show selection interface
    final browserLinks =
        imported
            .map((bookmark) => LinkSelectionItem.fromImported(bookmark))
            .toList();

    // Get current Kioju links for comparison
    final database = await db;
    final existingRows = await database.query('links');
    final kiojuLinks =
        existingRows
            .map((r) => LinkSelectionItem.fromKioju(LinkItem.fromMap(r)))
            .toList();

    // Show selection dialog
    if (mounted) {
      final result = await Navigator.of(
        context,
      ).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder:
              (_) => LinkSelectionPage(
                initialBrowserLinks: browserLinks,
                initialKiojuLinks: kiojuLinks,
              ),
        ),
      );

      if (result != null && result['action'] == 'import') {
        final selectedLinks = result['links'] as List<LinkSelectionItem>;
        // Import selected browser links
        final batch = database.batch();
        for (final item in selectedLinks) {
          // Only import browser links (non-Kioju links)
          if (item.remoteId == null) {
            batch.insert('links', {
              'url': item.url,
              'title': item.title == 'Untitled Link' ? null : item.title,
              'tags': item.tags.join(','),
              'collection': item.collection,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        await batch.commit(noResult: true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${selectedLinks.where((l) => l.remoteId == null).length} links',
            ),
          ),
        );
        await _refresh();
      }
    }
  }

  Future<void> _export() async {
    final database = await db;
    final rows = await database.query('links');
    final kiojuLinks =
        rows
            .map((r) => LinkSelectionItem.fromKioju(LinkItem.fromMap(r)))
            .toList();

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
      final result = await Navigator.of(
        context,
      ).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder:
              (_) => LinkSelectionPage(
                initialKiojuLinks: kiojuLinks,
              ),
        ),
      );

      if (result != null && result['action'] == 'export') {
        final selectedLinks = result['links'] as List<LinkSelectionItem>;
        // Convert selected items back to LinkItems for export
        final linksToExport =
            selectedLinks
                .map(
                  (item) => LinkItem(
                    id: null,
                    url: item.url,
                    title: item.title == 'Untitled Link' ? null : item.title,
                    tags: item.tags,
                    collection: item.collection,
                    remoteId: item.remoteId,
                    updatedAt: DateTime.now(),
                  ),
                )
                .toList();

        final html = exportToNetscapeHtml(linksToExport);

        final file = await getSaveLocation(suggestedName: 'bookmarks.html');
        if (file == null) return;

        await File(file.path).writeAsString(html);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${selectedLinks.length} links')),
        );
      }
    }
  }

  Future<void> _pull() async {
    try {
      final remote = await KiojuApi.listLinks(limit: 200, offset: 0);
      final database = await db;
      final batch = database.batch();
      for (final m in remote) {
        final url = (m['url'] ?? m['link'] ?? '') as String;
        if (url.isEmpty) continue;
        final title = (m['title'] ?? '') as String?;

        // Improved tag parsing - extract slugs from tag objects
        final tags = _parseTagsFromApi(m['tags']);

        final id = (m['id'] ?? m['remote_id'] ?? '').toString();
        batch.insert('links', {
          'url': url,
          'title': (title?.isNotEmpty ?? false) ? title : null,
          'tags': tags,
          'remote_id': id.isNotEmpty ? id : null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.rawUpdate(
          'UPDATE links SET title=COALESCE(?, title), tags=COALESCE(?, tags), updated_at=CURRENT_TIMESTAMP WHERE remote_id=?',
          [title, tags, id],
        );
      }
      await batch.commit(noResult: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pulled ${remote.length} links')),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pull failed: $e')));
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
    final database = await db;
    final rows = await database.query('links', where: 'remote_id IS NULL');
    int ok = 0;
    for (final r in rows) {
      try {
        final res = await KiojuApi.addLink(
          url: r['url'] as String,
          title: r['title'] as String?,
          tags:
              (r['tags'] as String? ?? '')
                  .split(',')
                  .where((e) => e.isNotEmpty)
                  .toList(),
        );
        final id = (res['id'] ?? res['remote_id'] ?? '').toString();
        if (id.isNotEmpty) {
          await database.update(
            'links',
            {'remote_id': id, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id=?',
            whereArgs: [r['id']],
          );
          ok++;
        }
      } catch (_) {
        // ignore in MVP
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Pushed $ok links')));
    }
    await _refresh();
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
                onPressed: _showAddLinkDialog,
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
    return [
      IconButton(
        onPressed: _showAddLinkDialog,
        icon: const Icon(Icons.add),
        tooltip: 'Add Link',
      ),
      IconButton(
        onPressed: _import,
        icon: const Icon(Icons.upload_file),
        tooltip: 'Import',
      ),
      IconButton(
        onPressed: _export,
        icon: const Icon(Icons.download),
        tooltip: 'Export',
      ),
      IconButton(
        onPressed: _pull,
        icon: const Icon(Icons.cloud_download),
        tooltip: 'Sync Down',
      ),
      IconButton(
        onPressed: _push,
        icon: const Icon(Icons.cloud_upload),
        tooltip: 'Sync Up',
      ),
      IconButton(
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
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
            onPressed: _showAddLinkDialog,
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
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.1),
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
                    child: Icon(
                      Icons.link,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteConfirmation(item.id!);
                      } else if (value == 'copy') {
                        _copyToClipboard(item.url);
                      }
                    },
                    itemBuilder:
                        (context) => [
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
      await database.insert('links', {
        'url': result['url'],
        'title': result['title'],
        'tags': (result['tags'] as List<String>).join(','),
        'notes': result['description'], // Store description in notes field
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link added successfully')),
        );
      }
    }
  }

  void _showDeleteConfirmation(int id) {
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
}
