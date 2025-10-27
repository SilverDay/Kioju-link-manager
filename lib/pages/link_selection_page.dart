import 'package:flutter/material.dart';
import '../models/link.dart';
import '../utils/bookmark_import.dart';
import '../services/kioju_api.dart';

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
  final String mode; // 'import' or 'export'
  final List<LinkSelectionItem>? initialBrowserLinks;
  final List<LinkSelectionItem>? initialKiojuLinks;

  const LinkSelectionPage({
    super.key,
    required this.mode,
    this.initialBrowserLinks,
    this.initialKiojuLinks,
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
    browserLinks = widget.initialBrowserLinks ?? [];
    kiojuLinks = widget.initialKiojuLinks ?? [];
    
    if (widget.mode == 'export' && kiojuLinks.isEmpty) {
      _loadKiojuLinks();
    }
  }

  Future<void> _loadKiojuLinks() async {
    setState(() => isLoading = true);
    
    try {
      final remote = await KiojuApi.listLinks(limit: 500, offset: 0);
      final items = remote.map((m) => LinkSelectionItem.fromApiResponse(m)).toList();
      setState(() {
        kiojuLinks = items;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load Kioju links: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  List<LinkSelectionItem> get filteredBrowserLinks {
    if (searchQuery.isEmpty) return browserLinks;
    return browserLinks.where((link) =>
      link.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
      link.url.toLowerCase().contains(searchQuery.toLowerCase()) ||
      link.tags.any((tag) => tag.toLowerCase().contains(searchQuery.toLowerCase()))).toList();
  }

  List<LinkSelectionItem> get filteredKiojuLinks {
    if (searchQuery.isEmpty) return kiojuLinks;
    return kiojuLinks.where((link) =>
      link.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
      link.url.toLowerCase().contains(searchQuery.toLowerCase()) ||
      link.tags.any((tag) => tag.toLowerCase().contains(searchQuery.toLowerCase()))).toList();
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
        title: Text(
          widget.mode == 'import' ? 'Select Links to Import' : 'Select Links to Export',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: _getSelectedLinks().isEmpty ? null : _handleConfirm,
            icon: Icon(widget.mode == 'import' ? Icons.download : Icons.upload),
            label: Text(widget.mode == 'import' ? 'Import Selected' : 'Export Selected'),
          ),
          const SizedBox(width: 8),
        ],
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

          // Selection Summary
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
                Text(
                  '${_getSelectedLinks().length} links selected for ${widget.mode}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
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
                _buildLinkList(filteredBrowserLinks, 'browser'),
                _buildLinkList(filteredKiojuLinks, 'kioju'),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
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
                child: _buildLinkList(filteredBrowserLinks, 'browser'),
              ),
            ],
          ),
        ),

        // Divider
        Container(
          width: 1,
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),

        // Kioju Links Side
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
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
                child: isLoading && kiojuLinks.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _buildLinkList(filteredKiojuLinks, 'kioju'),
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
              source == 'browser' ? 'No browser links loaded' : 'No Kioju links found',
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
      itemBuilder: (context, index) => _buildLinkSelectionCard(links[index]),
    );
  }

  Widget _buildLinkSelectionCard(LinkSelectionItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: item.isSelected 
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.isSelected 
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withOpacity(0.2),
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
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
                children: item.tags.take(3).map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
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

  List<LinkSelectionItem> _getSelectedLinks() {
    return [...browserLinks, ...kiojuLinks].where((link) => link.isSelected).toList();
  }

  void _handleConfirm() {
    final selectedLinks = _getSelectedLinks();
    Navigator.of(context).pop(selectedLinks);
  }
}