import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../db.dart';
import '../models/link.dart';
import '../utils/bookmark_export.dart';
import '../utils/bookmark_import.dart';
import '../services/link_service.dart';

class LinkSelectionItem {
  final String url;
  final String title;
  final List<String> tags;
  final String? collection;
  final String? remoteId;
  bool isSelected;

  LinkSelectionItem({
    required this.url,
    required this.title,
    required this.tags,
    this.collection,
    this.remoteId,
    this.isSelected = false,
  });

  factory LinkSelectionItem.fromImported(ImportedBookmark bookmark) {
    return LinkSelectionItem(
      url: bookmark.url,
      title: bookmark.title ?? 'Untitled Link',
      tags: bookmark.tags,
      collection: bookmark.collection,
    );
  }

  factory LinkSelectionItem.fromKioju(LinkItem link) {
    return LinkSelectionItem(
      url: link.url,
      title: link.title ?? 'Untitled Link',
      tags: link.tags,
      collection: link.collection,
      remoteId: link.remoteId,
    );
  }

  factory LinkSelectionItem.fromApiResponse(Map<String, dynamic> response) {
    final url = (response['url'] ?? response['link'] ?? '') as String;
    final title = (response['title'] ?? url) as String;
    final tags = _parseTagsFromApi(response['tags']);
    final remoteId = (response['id'] ?? response['remote_id'] ?? '').toString();

    return LinkSelectionItem(
      url: url,
      title: title,
      tags: tags.split(',').where((t) => t.isNotEmpty).toList(),
      remoteId: remoteId.isNotEmpty ? remoteId : null,
    );
  }

  static String _parseTagsFromApi(dynamic tagsRaw) {
    if (tagsRaw == null) return '';

    if (tagsRaw is List) {
      final tagSlugs = <String>[];
      for (final tagItem in tagsRaw) {
        if (tagItem is Map<String, dynamic>) {
          final slug = tagItem['slug']?.toString();
          if (slug?.isNotEmpty == true) {
            tagSlugs.add(slug!);
            continue;
          }
          final name = tagItem['name']?.toString();
          if (name?.isNotEmpty == true) {
            tagSlugs.add(name!);
            continue;
          }
        } else if (tagItem is String && tagItem.isNotEmpty) {
          tagSlugs.add(tagItem);
        }
      }
      return tagSlugs.join(',');
    } else if (tagsRaw is String) {
      return tagsRaw;
    }

    return '';
  }
}

class LinkSelectionPage extends StatefulWidget {
  final List<LinkSelectionItem>? initialBrowserLinks;
  final List<LinkSelectionItem>? initialKiojuLinks;
  final List<ImportedBookmark>? importedBookmarks;

  const LinkSelectionPage({
    super.key,
    this.initialBrowserLinks,
    this.initialKiojuLinks,
    this.importedBookmarks,
  });

  @override
  State<LinkSelectionPage> createState() => _LinkSelectionPageState();
}

class _LinkSelectionPageState extends State<LinkSelectionPage> {
  List<LinkSelectionItem> browserLinks = [];
  List<LinkSelectionItem> kiojuLinks = [];
  bool isLoading = false;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();

    // Convert imported bookmarks if provided
    if (widget.importedBookmarks != null) {
      browserLinks =
          widget.importedBookmarks!
              .map((bookmark) => LinkSelectionItem.fromImported(bookmark))
              .toList();
    } else {
      browserLinks = widget.initialBrowserLinks ?? [];
    }

    kiojuLinks = widget.initialKiojuLinks ?? [];

    // Always load Kioju links if not provided
    if (kiojuLinks.isEmpty) {
      _loadKiojuLinks();
    }
  }

  Future<void> _loadKiojuLinks() async {
    setState(() => isLoading = true);

    try {
      // Load from local database instead of API to show existing links
      final db = await AppDb.instance();
      final rows = await db.query('links', orderBy: 'created_at DESC');

      final items =
          rows.map((row) {
            final link = LinkItem.fromMap(row);
            return LinkSelectionItem.fromKioju(link);
          }).toList();

      setState(() {
        kiojuLinks = items;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load existing links: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  List<LinkSelectionItem> get filteredBrowserLinks {
    if (searchQuery.isEmpty) return browserLinks;
    return browserLinks
        .where(
          (link) =>
              link.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
              link.url.toLowerCase().contains(searchQuery.toLowerCase()) ||
              link.tags.any(
                (tag) => tag.toLowerCase().contains(searchQuery.toLowerCase()),
              ),
        )
        .toList();
  }

  List<LinkSelectionItem> get filteredKiojuLinks {
    if (searchQuery.isEmpty) return kiojuLinks;
    return kiojuLinks
        .where(
          (link) =>
              link.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
              link.url.toLowerCase().contains(searchQuery.toLowerCase()) ||
              link.tags.any(
                (tag) => tag.toLowerCase().contains(searchQuery.toLowerCase()),
              ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text(
          'Link Management',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
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
              onChanged: (value) => setState(() => searchQuery = value),
            ),
          ),

          // Info Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select links and use the "Copy to" buttons to transfer between browser bookmarks and Kioju',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Links Display
          Expanded(
            child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.web),
                text: 'Browser Links (${filteredBrowserLinks.length})',
              ),
              Tab(
                icon: const Icon(Icons.cloud),
                text: 'Kioju Links (${filteredKiojuLinks.length})',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: DragTarget<LinkSelectionItem>(
                        onWillAcceptWithDetails: (details) {
                          // Accept items from Kioju to export
                          return kiojuLinks.contains(details.data);
                        },
                        onAcceptWithDetails: (details) {
                          // Browser side accepts Kioju links for export
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Use the export button to save Kioju links',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        builder: (context, candidateData, rejectedData) {
                          return Container(
                            decoration:
                                candidateData.isNotEmpty
                                    ? BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.1),
                                      border: Border.all(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    )
                                    : null,
                            child: _buildLinkList(
                              filteredBrowserLinks,
                              'browser',
                            ),
                          );
                        },
                      ),
                    ),
                    if (_getSelectedBrowserLinks().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _copyBrowserLinksToKioju,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(
                              'Copy ${_getSelectedBrowserLinks().length} to Kioju',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Column(
                  children: [
                    Expanded(
                      child: DragTarget<LinkSelectionItem>(
                        onWillAcceptWithDetails: (details) {
                          // Accept items from browser to import
                          return browserLinks.contains(details.data);
                        },
                        onAcceptWithDetails: (details) async {
                          // Import the dropped link
                          final item = details.data;
                          setState(() => isLoading = true);

                          try {
                            await LinkService.instance.createLink(
                              url: item.url,
                              title:
                                  item.title == 'Untitled Link'
                                      ? null
                                      : item.title,
                              tags: item.tags,
                              collection: item.collection,
                              isPrivate: true,
                            );

                            // Reload Kioju links
                            await _loadKiojuLinks();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Imported "${item.title}"'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to import: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            setState(() => isLoading = false);
                          }
                        },
                        builder: (context, candidateData, rejectedData) {
                          return Container(
                            decoration:
                                candidateData.isNotEmpty
                                    ? BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.1),
                                      border: Border.all(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    )
                                    : null,
                            child:
                                isLoading && kiojuLinks.isEmpty
                                    ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                    : _buildLinkList(
                                      filteredKiojuLinks,
                                      'kioju',
                                    ),
                          );
                        },
                      ),
                    ),
                    if (_getSelectedKiojuLinks().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _copyKiojuLinksToBookmarks,
                            icon: const Icon(Icons.arrow_back),
                            label: Text(
                              'Copy ${_getSelectedKiojuLinks().length} to Bookmarks',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Browser Links Side
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                    Icon(
                      Icons.web,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Browser Links (${filteredBrowserLinks.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (filteredBrowserLinks.isNotEmpty) ...[
                      TextButton.icon(
                        onPressed: () => _selectAll(filteredBrowserLinks),
                        icon: const Icon(Icons.select_all, size: 16),
                        label: const Text('Select All'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _deselectAll(filteredBrowserLinks),
                        icon: const Icon(Icons.deselect, size: 16),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: DragTarget<LinkSelectionItem>(
                  onWillAcceptWithDetails: (details) {
                    // Accept items from Kioju to export
                    return kiojuLinks.contains(details.data);
                  },
                  onAcceptWithDetails: (details) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Use the export button to save Kioju links',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Container(
                      decoration:
                          candidateData.isNotEmpty
                              ? BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.1),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              )
                              : null,
                      child: _buildLinkList(filteredBrowserLinks, 'browser'),
                    );
                  },
                ),
              ),
              // Copy to Kioju button
              if (_getSelectedBrowserLinks().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _copyBrowserLinksToKioju,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        'Copy ${_getSelectedBrowserLinks().length} to Kioju',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Divider
        Container(
          width: 1,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),

        // Kioju Links Side
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                    Icon(
                      Icons.cloud,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Kioju Links (${filteredKiojuLinks.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (filteredKiojuLinks.isNotEmpty) ...[
                      TextButton.icon(
                        onPressed: () => _selectAll(filteredKiojuLinks),
                        icon: const Icon(Icons.select_all, size: 16),
                        label: const Text('Select All'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _deselectAll(filteredKiojuLinks),
                        icon: const Icon(Icons.deselect, size: 16),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: DragTarget<LinkSelectionItem>(
                  onWillAcceptWithDetails: (details) {
                    // Accept items from browser to import
                    return browserLinks.contains(details.data);
                  },
                  onAcceptWithDetails: (details) async {
                    // Import the dropped link
                    final item = details.data;
                    setState(() => isLoading = true);

                    try {
                      await LinkService.instance.createLink(
                        url: item.url,
                        title:
                            item.title == 'Untitled Link' ? null : item.title,
                        tags: item.tags,
                        collection: item.collection,
                        isPrivate: true,
                      );

                      // Reload Kioju links
                      await _loadKiojuLinks();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Imported "${item.title}"'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to import: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      setState(() => isLoading = false);
                    }
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Container(
                      decoration:
                          candidateData.isNotEmpty
                              ? BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.1),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              )
                              : null,
                      child:
                          isLoading && kiojuLinks.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : _buildLinkList(filteredKiojuLinks, 'kioju'),
                    );
                  },
                ),
              ),
              // Copy to Bookmarks button
              if (_getSelectedKiojuLinks().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _copyKiojuLinksToBookmarks,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        'Copy ${_getSelectedKiojuLinks().length} to Bookmarks',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkList(List<LinkSelectionItem> links, String source) {
    if (links.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              source == 'browser' ? Icons.web : Icons.cloud,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              source == 'browser'
                  ? 'No browser links loaded'
                  : 'No Kioju links found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: links.length,
      itemBuilder:
          (context, index) => _buildLinkSelectionCard(links[index], source),
    );
  }

  Widget _buildLinkSelectionCard(LinkSelectionItem item, String source) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color:
            item.isSelected
                ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              item.isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: CheckboxListTile(
        value: item.isSelected,
        onChanged: (bool? value) {
          setState(() {
            item.isSelected = value ?? false;
          });
        },
        title: Text(
          item.title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.url,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children:
                    item.tags
                        .take(3)
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );

    // Make browser links draggable to Kioju, and Kioju links draggable to export
    return Draggable<LinkSelectionItem>(
      data: item,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: 0.8,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      source == 'browser' ? Icons.web : Icons.cloud,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.url,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }

  void _selectAll(List<LinkSelectionItem> links) {
    setState(() {
      for (final link in links) {
        link.isSelected = true;
      }
    });
  }

  void _deselectAll(List<LinkSelectionItem> links) {
    setState(() {
      for (final link in links) {
        link.isSelected = false;
      }
    });
  }

  List<LinkSelectionItem> _getSelectedBrowserLinks() {
    return browserLinks.where((link) => link.isSelected).toList();
  }

  List<LinkSelectionItem> _getSelectedKiojuLinks() {
    return kiojuLinks.where((link) => link.isSelected).toList();
  }

  Future<void> _copyBrowserLinksToKioju() async {
    final selectedLinks = _getSelectedBrowserLinks();
    if (selectedLinks.isEmpty) return;

    // Show loading state
    setState(() => isLoading = true);

    int successCount = 0;
    int failureCount = 0;

    try {
      // Import each link using LinkService which respects sync settings
      for (final item in selectedLinks) {
        try {
          await LinkService.instance.createLink(
            url: item.url,
            title: item.title == 'Untitled Link' ? null : item.title,
            tags: item.tags,
            collection: item.collection,
            isPrivate: true,
          );
          successCount++;
        } catch (e) {
          failureCount++;
        }
      }

      // Clear selections and reload Kioju links
      setState(() {
        for (final link in selectedLinks) {
          link.isSelected = false;
        }
        isLoading = false;
      });

      // Reload Kioju links to show newly imported items
      await _loadKiojuLinks();

      if (!mounted) return;

      final message =
          failureCount == 0
              ? 'Successfully imported $successCount links'
              : 'Imported $successCount links ($failureCount failed)';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failureCount == 0 ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import links: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyKiojuLinksToBookmarks() async {
    final selectedLinks = _getSelectedKiojuLinks();
    if (selectedLinks.isEmpty) return;

    // Show loading state
    setState(() => isLoading = true);

    try {
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

      final html = _exportToNetscapeHtml(linksToExport);
      final file = await _getSaveLocation();

      if (file != null) {
        await File(file.path).writeAsString(html);

        // Clear selections and show success message
        setState(() {
          for (final link in selectedLinks) {
            link.isSelected = false;
          }
          isLoading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully exported ${selectedLinks.length} links to bookmarks.html',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export links: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper methods for file operations
  String _exportToNetscapeHtml(List<LinkItem> links) {
    return exportToNetscapeHtml(links);
  }

  Future<FileSaveLocation?> _getSaveLocation() async {
    return getSaveLocation(suggestedName: 'bookmarks.html');
  }
}
