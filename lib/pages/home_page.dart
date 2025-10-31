import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db.dart';
import '../models/collection.dart';
import '../models/link.dart';
import '../services/collection_service.dart';
import '../services/kioju_api.dart';
import '../services/sync_settings.dart';
import '../services/link_service.dart';

import '../utils/bookmark_import.dart';
import '../services/import_service.dart';
import '../widgets/add_link_dialog.dart';
import '../widgets/bulk_operations_dialog.dart';
import '../widgets/collection_tree_widget.dart';
import '../widgets/create_collection_dialog.dart';
import '../widgets/delete_collection_dialog.dart';
import '../widgets/edit_collection_dialog.dart';
import '../widgets/enhanced_search_bar.dart';
import '../widgets/import_conflict_dialog.dart';
import '../widgets/import_summary_dialog.dart';
import '../widgets/sync_conflict_dialog.dart';
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
  List<Collection> collections = [];
  List<LinkItem> uncategorizedLinks = [];
  Collection? _selectedCollection; // For search filtering

  // Services
  final CollectionService _collectionService = CollectionService.instance;
  final LinkService _linkService = LinkService.instance;

  // Progress tracking state
  bool _isImporting = false;
  bool _isExporting = false;
  bool _isSyncing = false;
  bool _isLoadingCollections = false;
  bool _forceOverwriteOnSync = false;

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
        final wasPremium = _isPremium;
        final isPremium = response['is_premium'] == true;

        setState(() {
          _isPremium = isPremium;
        });

        // If premium status changed, refresh the view
        if (wasPremium != isPremium) {
          await _refresh();
        }
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
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      )
                      .then((_) async {
                        if (mounted) {
                          setState(() {});
                          _checkFirstTimeSetup();
                          await _refresh();
                        }
                      });
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
                      .then((_) async {
                        // Recheck setup after settings page
                        if (mounted) {
                          setState(() {});
                          _checkFirstTimeSetup();
                          await _refresh();
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

    // Build where clause for search and collection filtering
    List<String> whereConditions = [];
    List<dynamic> whereArgs = [];

    // Add search conditions
    if (q.isNotEmpty) {
      whereConditions.add('(url LIKE ? OR title LIKE ? OR notes LIKE ?)');
      whereArgs.addAll(['%$q%', '%$q%', '%$q%']);
    }

    // Add collection filtering
    if (_selectedCollection != null) {
      if (_selectedCollection!.name == '_uncategorized') {
        // Filter for uncategorized links
        whereConditions.add('(collection IS NULL OR collection = "")');
      } else {
        // Filter for specific collection
        whereConditions.add('collection = ?');
        whereArgs.add(_selectedCollection!.name);
      }
    }

    // Load filtered links
    final rows = await database.query(
      'links',
      where: whereConditions.isEmpty ? null : whereConditions.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'updated_at DESC',
      limit: 500,
    );
    final allLinks = rows.map((r) => LinkItem.fromMap(r)).toList();

    // Load collections if premium user
    if (_isPremium == true) {
      await _loadCollections();

      // Separate uncategorized links (only if not filtering by collection)
      final uncategorized =
          _selectedCollection == null
              ? allLinks
                  .where(
                    (link) =>
                        link.collection == null || link.collection!.isEmpty,
                  )
                  .toList()
              : <LinkItem>[];

      setState(() {
        items = allLinks;
        uncategorizedLinks = uncategorized;
      });
    } else {
      // For non-premium users, show flat list
      setState(() {
        items = allLinks;
        collections = [];
        uncategorizedLinks = allLinks;
      });
    }
  }

  Future<void> _loadCollections() async {
    if (_isLoadingCollections) return;

    setState(() {
      _isLoadingCollections = true;
    });

    try {
      final loadedCollections = await _collectionService.getCollections();
      setState(() {
        collections = loadedCollections;
        _isLoadingCollections = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCollections = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load collections: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    _refresh();
  }

  void _onCollectionFilterChanged(Collection? collection) {
    setState(() {
      _selectedCollection = collection;
    });
    _refresh();
  }

  String _buildSearchResultsText() {
    final searchQuery = _searchCtrl.text.trim();
    final hasSearch = searchQuery.isNotEmpty;
    final hasCollectionFilter = _selectedCollection != null;

    if (hasSearch && hasCollectionFilter) {
      if (_selectedCollection!.name == '_uncategorized') {
        return 'Showing uncategorized links matching "$searchQuery" (${items.length} results)';
      } else {
        return 'Showing links in "${_selectedCollection!.name}" matching "$searchQuery" (${items.length} results)';
      }
    } else if (hasSearch) {
      return 'Showing links matching "$searchQuery" (${items.length} results)';
    } else if (hasCollectionFilter) {
      if (_selectedCollection!.name == '_uncategorized') {
        return 'Showing uncategorized links (${items.length} links)';
      } else {
        return 'Showing links in "${_selectedCollection!.name}" (${items.length} links)';
      }
    }

    return '';
  }

  Future<void> _showBulkOperationsDialog(List<LinkItem> selectedLinks) async {
    if (selectedLinks.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder:
          (context) => BulkOperationsDialog(
            selectedLinks: selectedLinks,
            collections: collections,
            onOperationComplete: () {
              _refresh(); // Refresh the view after bulk operation
            },
          ),
    );
  }

  Future<void> _delete(int id) async {
    try {
      final syncResult = await _linkService.deleteLink(linkId: id);

      await _refresh();

      if (mounted) {
        final message = LinkService.formatSyncResultMessage(
          syncResult,
          'Link deleted',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  syncResult.success ? Icons.check : Icons.error,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor:
                syncResult.success
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
            duration: Duration(seconds: syncResult.success ? 3 : 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete link: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
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

      _updateProgressDialog('Parsing bookmarks and creating collections...');

      // First pass: Parse bookmarks and handle collection conflicts
      ImportResult initialResult;
      if (path.endsWith('.html') ||
          text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
        initialResult = await importFromNetscapeHtml(
          text,
          createCollections: true,
        );
      } else if (path.endsWith('.json')) {
        initialResult = await importFromChromeJson(
          jsonDecode(text),
          createCollections: true,
        );
      } else {
        throw Exception('Unsupported file format');
      }

      if (initialResult.bookmarks.isEmpty) {
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

      // Handle collection conflicts if any
      Map<String, String>? collectionMappings;
      if (initialResult.collectionConflicts.isNotEmpty) {
        _hideProgressDialog();

        if (mounted) {
          await showDialog<void>(
            context: context,
            builder:
                (context) => ImportConflictDialog(
                  conflictingCollections: initialResult.collectionConflicts,
                  onResolved: (resolutions) {
                    collectionMappings = resolutions;
                  },
                ),
          );
        }

        // If user cancelled conflict resolution, abort import
        if (collectionMappings == null) {
          return;
        }
      }

      // Second pass: Import with sync strategy
      _updateProgressDialog(
        'Importing ${initialResult.bookmarks.length} links...',
      );

      ImportSyncResult importSyncResult;
      if (path.endsWith('.html') ||
          text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
        importSyncResult = await ImportService.instance.importFromHtml(
          text,
          createCollections: true,
          collectionNameMappings: collectionMappings,
          onProgress: (completed, total) {
            _updateProgressDialog('Importing links... ($completed/$total)');
          },
        );
      } else {
        importSyncResult = await ImportService.instance.importFromJson(
          jsonDecode(text),
          createCollections: true,
          collectionNameMappings: collectionMappings,
          onProgress: (completed, total) {
            _updateProgressDialog('Importing links... ($completed/$total)');
          },
        );
      }

      _hideProgressDialog();

      // Show import summary with sync results
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder:
              (context) => ImportSummaryDialog(
                importResult: importSyncResult.importResult,
                linksImported: importSyncResult.totalLinksProcessed,
                syncResult: importSyncResult,
              ),
        );

        // Always refresh after import
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

  // Collection management methods
  Future<void> _createCollection() async {
    if (_requiresPremiumWarning) {
      _showPremiumRequiredDialog('Collection Management');
      return;
    }

    final result = await showCreateCollectionDialog(context);
    if (result == null) return;

    try {
      await _collectionService.createCollection(
        name: result['name'],
        description: result['description'],
        visibility: result['visibility'],
      );

      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      if (!mounted) return;
      final message =
          isImmediateSync
              ? 'Collection created and synced successfully'
              : 'Collection created locally. Use sync to upload changes.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      await _refresh();
    } catch (e) {
      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      final syncFailed =
          isImmediateSync && e.toString().contains('Sync operation failed');
      if (!mounted) return;
      final message =
          syncFailed
              ? 'Collection created locally, but server sync failed: ${e.toString()}'
              : 'Failed to create collection: ${e.toString()}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );

      if (syncFailed) {
        await _refresh();
      }
    }
  }

  Future<void> _editCollection(Collection collection) async {
    final result = await showEditCollectionDialog(context, collection);
    if (result == null) return;

    try {
      await _collectionService.updateCollection(
        id: result['id'],
        name: result['name'],
        description: result['description'],
        visibility: result['visibility'],
      );

      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      if (!mounted) return;
      final message =
          isImmediateSync
              ? 'Collection updated and synced successfully'
              : 'Collection updated locally. Use sync to upload changes.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      await _refresh();

      if (result['name'] != collection.name) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final updatedCollection = collections.firstWhere(
            (c) => c.id == collection.id,
            orElse: () => collection,
          );
          collectionTreeKey.currentState?.refreshCollection(updatedCollection);
        });
      }
    } catch (e) {
      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      final syncFailed =
          isImmediateSync && e.toString().contains('Sync operation failed');
      if (!mounted) return;
      final message =
          syncFailed
              ? 'Collection updated locally, but server sync failed: ${e.toString()}'
              : 'Failed to update collection: ${e.toString()}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );

      if (syncFailed) {
        await _refresh();
      }
    }
  }

  Future<void> _deleteCollection(Collection collection) async {
    final result = await showDeleteCollectionDialog(context, collection);
    if (result == null) return;

    try {
      await _collectionService.deleteCollection(
        collection.id!,
        deleteMode: result['linkHandling'],
      );

      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      if (!mounted) return;
      final message =
          isImmediateSync
              ? 'Collection deleted and synced successfully'
              : 'Collection deleted locally. Use sync to upload changes.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      await _refresh();
    } catch (e) {
      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      final syncFailed =
          isImmediateSync && e.toString().contains('Sync operation failed');
      if (!mounted) return;
      final message =
          syncFailed
              ? 'Collection deleted locally, but server sync failed: ${e.toString()}'
              : 'Failed to delete collection: ${e.toString()}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );

      if (syncFailed) {
        await _refresh();
      }
    }
  }

  Future<void> _moveLink(LinkItem link, String? collectionId) async {
    try {
      final syncResult = await _linkService.moveLink(
        linkId: link.id!,
        toCollection: collectionId,
      );

      if (!mounted) return;
      final operationName =
          collectionId == null
              ? 'Link moved to uncategorized'
              : 'Link moved to collection';
      final message = LinkService.formatSyncResultMessage(
        syncResult,
        operationName,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                syncResult.success ? Icons.check : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor:
              syncResult.success
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
          duration: Duration(seconds: syncResult.success ? 3 : 5),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to move link: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _pull() async {
    if (_isSyncing) return; // Prevent multiple simultaneous syncs

    // Check premium status for list operation
    if (_requiresPremiumWarning) {
      _showPremiumRequiredDialog('Sync Down (List)');
      return;
    }

    // Check for unsynced changes if premium user
    if (_isPremium == true) {
      try {
        final hasUnsynced = await _collectionService.hasUnsyncedChanges();
        if (hasUnsynced) {
          final unsyncedCounts =
              await _collectionService.getUnsyncedChangesCount();
          if (!mounted) return;
          final action = await showSyncConflictDialog(
            context,
            unsyncedCollections: unsyncedCounts['collections'] ?? 0,
            unsyncedLinks: unsyncedCounts['links'] ?? 0,
          );

          if (action == 'cancel') {
            return;
          } else if (action == 'sync_up_first') {
            await _push();
            return;
          }
          // If action == 'continue', proceed with sync down with forceOverwrite
          if (action == 'continue') {
            // Set flag to force overwrite local changes

            _forceOverwriteOnSync = true;
          }
        }
      } catch (e) {
        // If we can't check for unsynced changes, proceed with caution
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Warning: Could not check for local changes: ${e.toString()}',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
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

      // For premium users, fetch links via collections to get proper categorization
      List<Map<String, dynamic>> allRemoteLinks = [];

      if (_isPremium == true) {
        // First sync collections to ensure we have the latest collection list
        _updateProgressDialog('Syncing collections...');
        try {
          await _collectionService.syncDown(
            forceOverwrite: _forceOverwriteOnSync,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Collection sync failed: ${e.toString()}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }

        // Get all collections from collection service AFTER sync is complete
        // This ensures we get the most up-to-date collection list
        final collectionObjects = await _collectionService.getCollections();
        final collections =
            collectionObjects
                .where((c) => c.remoteId != null)
                .map(
                  (c) => {'name': c.name, 'remote_id': c.remoteId, 'id': c.id},
                )
                .toList();

        // Fetch links for each collection
        for (int i = 0; i < collections.length; i++) {
          final collection = collections[i];
          final collectionName = collection['name'] as String;
          final remoteId = collection['remote_id'] as String;

          _updateProgressDialog(
            'Downloading links from "$collectionName" (${i + 1}/${collections.length})...',
          );

          try {
            final response = await KiojuApi.getCollectionLinks(remoteId);

            if (response['success'] == true && response['links'] != null) {
              final linksList = response['links'] as List<dynamic>;
              final collectionLinks = linksList.cast<Map<String, dynamic>>();

              // Add collection name to each link
              for (final link in collectionLinks) {
                link['_collection_name'] = collectionName;
              }

              allRemoteLinks.addAll(collectionLinks);
            }
          } catch (e) {
            // Check if this is a 404 error (collection doesn't exist on API)
            if (e.toString().contains('404') ||
                e.toString().contains('not found')) {
              // Don't show error to user for 404s, just continue with other collections
            } else {
              // Show error for other types of failures
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Failed to sync collection "$collectionName": ${e.toString()}',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          }
        }

        // Also fetch uncategorized links
        _updateProgressDialog('Downloading uncategorized links...');
        try {
          final response = await KiojuApi.getUncategorizedLinks();

          if (response['success'] == true && response['links'] != null) {
            final linksList = response['links'] as List<dynamic>;
            final uncategorizedLinks = linksList.cast<Map<String, dynamic>>();

            // Mark these as uncategorized (no collection)
            for (final link in uncategorizedLinks) {
              link['_collection_name'] = null;
            }

            allRemoteLinks.addAll(uncategorizedLinks);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to sync uncategorized links: ${e.toString()}',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        // For non-premium users, use the regular list API
        int offset = 0;
        const int batchSize = 100;

        while (true) {
          _updateProgressDialog(
            'Downloading batch ${(offset / batchSize + 1).toInt()}...',
          );

          final batch = await KiojuApi.listLinks(
            limit: batchSize,
            offset: offset,
          );
          if (batch.isEmpty) break;

          allRemoteLinks.addAll(batch);
          offset += batchSize;

          if (batch.length < batchSize) break;
        }
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
        final collectionName =
            m['_collection_name']
                as String?; // Collection info from our API calls

        // Improved tag parsing - extract slugs from tag objects
        final tags = _parseTagsFromApi(m['tags']);

        final id = (m['id'] ?? m['remote_id'] ?? '').toString();

        // Use INSERT OR REPLACE to handle URL conflicts properly
        batch.rawInsert(
          '''
          INSERT OR REPLACE INTO links (
            url, title, notes, tags, collection, is_private, remote_id, 
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 
            COALESCE((SELECT created_at FROM links WHERE url = ?), CURRENT_TIMESTAMP),
            CURRENT_TIMESTAMP
          )
        ''',
          [
            url,
            (title?.isNotEmpty ?? false) ? title : null,
            (description?.isNotEmpty ?? false) ? description : null,
            tags,
            collectionName,
            (isPrivate is bool
                    ? isPrivate
                    : (isPrivate == 1 || isPrivate == '1'))
                ? 1
                : 0,
            id.isNotEmpty ? id : null,
            url, // For the COALESCE created_at lookup
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

      // Debug: Check what's actually in the database after sync
      final dbInstance = await db;
      final allLinks = await dbInstance.query('links');
      final collectionsInDb = <String, int>{};

      for (final link in allLinks) {
        final collection = link['collection'] as String?;
        final key = collection ?? 'UNCATEGORIZED';
        collectionsInDb[key] = (collectionsInDb[key] ?? 0) + 1;
      }

      // Update collection link counts after sync
      await _collectionService.updateCollectionLinkCounts();

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
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    )
                    .then((_) async {
                      if (mounted) {
                        setState(() {});
                        _checkFirstTimeSetup();
                        await _refresh();
                      }
                    });
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
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    )
                    .then((_) async {
                      if (mounted) {
                        setState(() {});
                        _checkFirstTimeSetup();
                        await _refresh();
                      }
                    });
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
          _forceOverwriteOnSync = false; // Reset the flag
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
      // Check if there are any changes to sync
      final pendingChanges = await _collectionService.getPendingChangesCount();
      if (pendingChanges['total'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No changes to sync')));
        }
        setState(() {
          _isSyncing = false;
        });
        return;
      }

      _showProgressDialog('Syncing Up', 'Syncing changes to Kioju...');

      // Use the CollectionService's efficient sync method
      final syncResult = await _collectionService.syncUp();

      _hideProgressDialog();

      if (mounted) {
        if (syncResult['success'] == true) {
          final collectionsCount = syncResult['collections_synced'] ?? 0;
          final linksCount = syncResult['links_synced'] ?? 0;
          final totalSynced = collectionsCount + linksCount;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced $totalSynced items successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          final errors = syncResult['errors'] as List<String>? ?? [];
          final errorMessage =
              errors.isNotEmpty
                  ? errors.first
                  : 'Sync failed with unknown error';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: $errorMessage'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }

      await _refresh();
    } catch (e) {
      _hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
          // Enhanced Search Section
          EnhancedSearchBar(
            searchController: _searchCtrl,
            collections: collections,
            selectedCollection: _selectedCollection,
            onSearchChanged: _onSearchChanged,
            onCollectionChanged: _onCollectionFilterChanged,
            showCollectionFilter: _isPremium == true,
          ),

          // Links List Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  _isPremium == true ? 'Your Collections' : 'Your Links',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                if (_isPremium == true) ...[
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
                      '${collections.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length} links',
                      style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else
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

          // Search results indicator
          if (_selectedCollection != null || _searchCtrl.text.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _buildSearchResultsText(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Collection Tree or Links List
          Expanded(
            child:
                _isPremium == true
                    ? (collections.isEmpty &&
                            uncategorizedLinks.isEmpty &&
                            !_isLoadingCollections)
                        ? _buildEmptyState()
                        : CollectionTreeWidget(
                          key: collectionTreeKey,
                          collections: collections,
                          uncategorizedLinks: uncategorizedLinks,
                          onLinkTap: (link) => _openUrl(link.url),
                          onLinkEdit: _showEditLinkDialog,
                          onLinkDelete:
                              (link) => _showDeleteConfirmation(link.id!),
                          onLinkCopy: (link) => _copyToClipboard(link.url),
                          onCollectionEdit: _editCollection,
                          onCollectionDelete: _deleteCollection,
                          onCreateCollection: _createCollection,
                          onLinkMoved: _moveLink,
                          onBulkOperation: _showBulkOperationsDialog,
                          isLoading: _isLoadingCollections,
                        )
                    : items.isEmpty
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
                  if (mounted) {
                    setState(() {});
                    _checkFirstTimeSetup();
                    await _refresh();
                  }
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
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsPage())).then((
          _,
        ) async {
          // Check if token was set and refresh UI
          if (mounted) {
            setState(() {});
            _checkFirstTimeSetup();
            // Refresh all data in case database was cleared or other changes were made
            await _refresh();
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
          // Update existing link using LinkService
          try {
            final linkId = existingLink['id'] as int;
            final syncResult = await _linkService.updateLink(
              linkId: linkId,
              title: result['title'],
              description: result['description'],
              tags: result['tags'] as List<String>,
              isPrivate: result['isPrivate'] == true,
            );

            await _refresh();

            if (mounted) {
              final message = LinkService.formatSyncResultMessage(
                syncResult,
                'Link updated',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        syncResult.success ? Icons.check : Icons.error,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(message)),
                    ],
                  ),
                  backgroundColor:
                      syncResult.success
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                  duration: Duration(seconds: syncResult.success ? 3 : 5),
                ),
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
      } else {
        // URL doesn't exist, add new link using LinkService
        try {
          final syncResult = await _linkService.createLink(
            url: result['url'],
            title: result['title'],
            description: result['description'],
            tags: result['tags'] as List<String>,
            isPrivate: result['isPrivate'] == true,
          );

          await _refresh();

          if (mounted) {
            final message = LinkService.formatSyncResultMessage(
              syncResult,
              'Link added',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      syncResult.success ? Icons.check : Icons.error,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(message)),
                  ],
                ),
                backgroundColor:
                    syncResult.success
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                duration: Duration(seconds: syncResult.success ? 3 : 5),
              ),
            );
          }
        } catch (e) {
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
        final syncResult = await _linkService.updateLink(
          linkId: item.id!,
          title: result['title'],
          description: result['description'],
          tags: result['tags'] as List<String>,
          isPrivate: result['isPrivate'] == true,
          collection: item.collection,
        );

        await _refresh();

        if (mounted) {
          final message = LinkService.formatSyncResultMessage(
            syncResult,
            'Link updated',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    syncResult.success ? Icons.check : Icons.error,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message)),
                ],
              ),
              backgroundColor:
                  syncResult.success
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
              duration: Duration(seconds: syncResult.success ? 3 : 5),
            ),
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
