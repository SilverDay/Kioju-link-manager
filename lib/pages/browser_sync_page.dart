import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../db.dart';
import '../models/link.dart';
import '../utils/bookmark_import.dart';
import '../services/link_service.dart';
import '../services/import_export_service.dart';

class BrowserSyncPage extends StatefulWidget {
  const BrowserSyncPage({super.key});

  @override
  State<BrowserSyncPage> createState() => _BrowserSyncPageState();
}

class _BrowserSyncPageState extends State<BrowserSyncPage> {
  // State management
  List<ImportedBookmark> _browserBookmarks = [];
  List<LinkItem> _kiojuLinks = [];
  String? _loadedBookmarkFile;
  bool _isLoading = false;
  String _loadingMessage = '';

  // Selection state
  final Set<String> _selectedBrowserBookmarks = {};
  final Set<int> _selectedKiojuLinks = {};

  @override
  void initState() {
    super.initState();
    _loadKiojuLinks();
  }

  Future<void> _loadKiojuLinks() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Loading Kioju links...';
    });

    try {
      final db = await AppDb.instance();
      final rows = await db.query('links', orderBy: 'title ASC');
      _kiojuLinks = rows.map((row) => LinkItem.fromMap(row)).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load Kioju links: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBookmarkFile() async {
    final typeGroup = XTypeGroup(
      label: 'Bookmarks',
      extensions: ['html', 'json'],
    );
    final xfile = await openFile(acceptedTypeGroups: [typeGroup]);
    if (xfile == null) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Loading bookmark file...';
    });

    try {
      final path = xfile.path;
      final text = await xfile.readAsString();

      ImportResult importResult;
      if (path.endsWith('.html') ||
          text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
        importResult = await importFromNetscapeHtml(
          text,
          createCollections: false,
        );
      } else if (path.endsWith('.json')) {
        importResult = await importFromChromeJson(
          jsonDecode(text),
          createCollections: false,
        );
      } else {
        throw Exception('Unsupported file format');
      }

      setState(() {
        _browserBookmarks = importResult.bookmarks;
        _loadedBookmarkFile = path.split('/').last;
        _selectedBrowserBookmarks.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Loaded ${_browserBookmarks.length} bookmarks from $_loadedBookmarkFile',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load bookmark file: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _syncSelectedToKioju() async {
    if (_selectedBrowserBookmarks.isEmpty) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Syncing to Kioju...';
    });

    try {
      final linkService = LinkService.instance;
      int imported = 0;
      final errors = <String>[];

      for (final bookmarkUrl in _selectedBrowserBookmarks) {
        final bookmark = _browserBookmarks.firstWhere(
          (b) => b.url == bookmarkUrl,
        );

        try {
          final result = await linkService.createLink(
            url: bookmark.url,
            title: bookmark.title,
            tags: bookmark.tags,
            collection: bookmark.collection,
          );

          if (result.success) {
            imported++;
          } else {
            errors.add('${bookmark.url}: ${result.errorMessage}');
          }
        } catch (e) {
          errors.add('${bookmark.url}: $e');
        }
      }

      // Refresh Kioju links
      await _loadKiojuLinks();

      // Clear selections
      setState(() {
        _selectedBrowserBookmarks.clear();
      });

      if (mounted) {
        final message =
            errors.isEmpty
                ? 'Successfully imported $imported bookmarks to Kioju'
                : 'Imported $imported bookmarks with ${errors.length} errors';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: errors.isEmpty ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportSelectedToBrowser() async {
    if (_selectedKiojuLinks.isEmpty) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Exporting to browser...';
    });

    try {
      final selectedLinks =
          _kiojuLinks
              .where((link) => _selectedKiojuLinks.contains(link.id))
              .toList();

      final exportService = ImportExportService();
      final result = await exportService.exportToBrowser(selectedLinks);

      if (result.success) {
        setState(() {
          _selectedKiojuLinks.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result.error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Export failed: ${result.error}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
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
                color: Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.sync_alt,
                color: Theme.of(context).colorScheme.onSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Browser Sync',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body:
          _isLoading
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_loadingMessage),
                  ],
                ),
              )
              : Column(
                children: [
                  // Action buttons
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Load bookmark file
                        ElevatedButton.icon(
                          onPressed: _loadBookmarkFile,
                          icon: const Icon(Icons.file_open),
                          label: Text(
                            _loadedBookmarkFile ?? 'Load Bookmark File',
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Sync actions
                        if (_selectedBrowserBookmarks.isNotEmpty) ...[
                          ElevatedButton.icon(
                            onPressed: _syncSelectedToKioju,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(
                              'Import ${_selectedBrowserBookmarks.length} to Kioju',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (_selectedKiojuLinks.isNotEmpty) ...[
                          ElevatedButton.icon(
                            onPressed: _exportSelectedToBrowser,
                            icon: const Icon(Icons.arrow_back),
                            label: Text(
                              'Export ${_selectedKiojuLinks.length} to Browser',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Content area
                  Expanded(
                    child: Row(
                      children: [
                        // Browser bookmarks side
                        Expanded(child: _buildBrowserBookmarksPanel()),
                        // Divider
                        Container(
                          width: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                        // Kioju links side
                        Expanded(child: _buildKiojuLinksPanel()),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildBrowserBookmarksPanel() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.web, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Browser Bookmarks',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_browserBookmarks.isNotEmpty) ...[
                Text(
                  '${_browserBookmarks.length} bookmarks',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedBrowserBookmarks.length ==
                          _browserBookmarks.length) {
                        _selectedBrowserBookmarks.clear();
                      } else {
                        _selectedBrowserBookmarks.clear();
                        _selectedBrowserBookmarks.addAll(
                          _browserBookmarks.map((b) => b.url),
                        );
                      }
                    });
                  },
                  child: Text(
                    _selectedBrowserBookmarks.length == _browserBookmarks.length
                        ? 'Deselect All'
                        : 'Select All',
                  ),
                ),
              ],
            ],
          ),
        ),
        // Content
        Expanded(
          child:
              _browserBookmarks.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.file_open,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No bookmark file loaded',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Load Bookmark File" to get started',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    itemCount: _browserBookmarks.length,
                    itemBuilder: (context, index) {
                      final bookmark = _browserBookmarks[index];
                      final isSelected = _selectedBrowserBookmarks.contains(
                        bookmark.url,
                      );

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedBrowserBookmarks.add(bookmark.url);
                            } else {
                              _selectedBrowserBookmarks.remove(bookmark.url);
                            }
                          });
                        },
                        title: Text(
                          bookmark.title ?? bookmark.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bookmark.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (bookmark.collection != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  bookmark.collection!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        dense: true,
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildKiojuLinksPanel() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.bookmark,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Kioju Links',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_kiojuLinks.isNotEmpty) ...[
                Text(
                  '${_kiojuLinks.length} links',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedKiojuLinks.length == _kiojuLinks.length) {
                        _selectedKiojuLinks.clear();
                      } else {
                        _selectedKiojuLinks.clear();
                        _selectedKiojuLinks.addAll(
                          _kiojuLinks
                              .where((link) => link.id != null)
                              .map((link) => link.id!),
                        );
                      }
                    });
                  },
                  child: Text(
                    _selectedKiojuLinks.length == _kiojuLinks.length
                        ? 'Deselect All'
                        : 'Select All',
                  ),
                ),
              ],
            ],
          ),
        ),
        // Content
        Expanded(
          child:
              _kiojuLinks.isEmpty
                  ? Center(
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
                          'No Kioju links found',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add some links in the main app first',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    itemCount: _kiojuLinks.length,
                    itemBuilder: (context, index) {
                      final link = _kiojuLinks[index];
                      final isSelected = _selectedKiojuLinks.contains(link.id);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged:
                            link.id == null
                                ? null
                                : (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedKiojuLinks.add(link.id!);
                                    } else {
                                      _selectedKiojuLinks.remove(link.id);
                                    }
                                  });
                                },
                        title: Text(
                          link.title ?? link.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              link.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (link.collection != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  link.collection!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        dense: true,
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
