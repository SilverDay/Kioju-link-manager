import 'package:flutter/material.dart';
import '../models/collection.dart';
import '../models/link.dart';
import '../services/collection_service.dart';

class CollectionTreeWidget extends StatefulWidget {
  final List<Collection> collections;
  final List<LinkItem> uncategorizedLinks;
  final Function(LinkItem) onLinkTap;
  final Function(LinkItem) onLinkEdit;
  final Function(LinkItem) onLinkDelete;
  final Function(LinkItem) onLinkCopy;
  final Function(Collection) onCollectionEdit;
  final Function(Collection) onCollectionDelete;
  final Function() onCreateCollection;
  final Function(LinkItem, String?) onLinkMoved; // null collection means uncategorized
  final bool isLoading;
  final Function(List<LinkItem>)? onBulkOperation; // New callback for bulk operations

  const CollectionTreeWidget({
    super.key,
    required this.collections,
    required this.uncategorizedLinks,
    required this.onLinkTap,
    required this.onLinkEdit,
    required this.onLinkDelete,
    required this.onLinkCopy,
    required this.onCollectionEdit,
    required this.onCollectionDelete,
    required this.onCreateCollection,
    required this.onLinkMoved,
    this.isLoading = false,
    this.onBulkOperation,
  });

  @override
  State<CollectionTreeWidget> createState() => CollectionTreeWidgetState();
}

// Global key to access the collection tree widget state
final GlobalKey<CollectionTreeWidgetState> collectionTreeKey = GlobalKey<CollectionTreeWidgetState>();

class CollectionTreeWidgetState extends State<CollectionTreeWidget> {
  final Set<String> _expandedCollections = <String>{};
  final CollectionService _collectionService = CollectionService.instance;
  final Map<String, List<LinkItem>> _collectionLinks = {};
  final Map<String, bool> _loadingCollections = {};
  final Map<String, bool> _hasMoreLinks = {}; // Track if collection has more links to load
  final Map<String, int> _loadedPages = {}; // Track how many pages loaded per collection
  final Set<int> _selectedLinkIds = <int>{}; // Track selected links
  bool _isMultiSelectMode = false;
  final int _uncategorizedLinksShown = 50; // Show limited uncategorized links initially
  
  static const int _linksPerPage = 50; // Load links in batches

  @override
  void initState() {
    super.initState();
    // Don't load all collections on init - use lazy loading instead
  }

  @override
  void didUpdateWidget(CollectionTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear cache if collections changed significantly
    if (oldWidget.collections.length != widget.collections.length) {
      _collectionLinks.clear();
      _loadingCollections.clear();
      _hasMoreLinks.clear();
      _loadedPages.clear();
    } else {
      // Check if any collection data has changed (like link counts)
      bool collectionsChanged = false;
      for (int i = 0; i < widget.collections.length; i++) {
        if (i >= oldWidget.collections.length) {
          collectionsChanged = true;
          break;
        }
        final newCollection = widget.collections[i];
        final oldCollection = oldWidget.collections[i];
        
        // Check if link count or other key properties changed
        if (newCollection.linkCount != oldCollection.linkCount ||
            newCollection.name != oldCollection.name ||
            newCollection.updatedAt != oldCollection.updatedAt) {
          collectionsChanged = true;
          break;
        }
      }
      
      // If collections data changed, clear the cache to force reload
      if (collectionsChanged) {
        _collectionLinks.clear();
        _loadingCollections.clear();
        _hasMoreLinks.clear();
        _loadedPages.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // Multi-select toolbar
            if (_isMultiSelectMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildMultiSelectToolbar(),
                ),
              ),
            
            // Collections as folders (optimized for large lists)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: widget.collections.length,
                itemBuilder: (context, index) {
                  return _buildCollectionFolder(widget.collections[index]);
                },
              ),
            ),
            
            // Uncategorized links section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildUncategorizedSection(),
                    const SizedBox(height: 16),
                    _buildAddCollectionButton(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        
        // Floating bulk operations toolbar
        if (_isMultiSelectMode && _selectedLinkIds.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildBulkOperationsBar(),
          ),
      ],
    );
  }

  Widget _buildCollectionFolder(Collection collection) {
    final collectionId = collection.remoteId ?? 'local_${collection.id}';
    final isExpanded = _expandedCollections.contains(collectionId);
    final links = _collectionLinks[collectionId] ?? [];
    final isLoading = _loadingCollections[collectionId] == true;
    // Always show the actual collection link count from the database, not just loaded links
    final linkCount = collection.linkCount;

    return Column(
      children: [
        // Collection header with drag-and-drop target
        DragTarget<LinkItem>(
          onAcceptWithDetails: (details) {
            final link = details.data;
            widget.onLinkMoved(link, collection.name);
          },
          builder: (context, candidateData, rejectedData) {
            final isDragOver = candidateData.isNotEmpty;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isDragOver
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDragOver
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  width: isDragOver ? 2 : 1,
                ),
              ),
              child: InkWell(
                onTap: () => _toggleCollection(collectionId),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.folder_open : Icons.folder,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          collection.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '$linkCount',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        onSelected: (value) => _handleCollectionAction(value, collection),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit),
                              title: Text('Edit Collection'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete, color: Colors.red),
                              title: Text('Delete Collection', style: TextStyle(color: Colors.red)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        
        // Collection links (when expanded)
        if (isExpanded) ...[
          if (isLoading)
            Container(
              margin: const EdgeInsets.only(left: 32, bottom: 8),
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (links.isEmpty)
            Container(
              margin: const EdgeInsets.only(left: 32, bottom: 8),
              padding: const EdgeInsets.all(16),
              child: Text(
                'No links in this collection',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...links.map((link) => Container(
              margin: const EdgeInsets.only(left: 32, bottom: 8),
              child: _buildLinkItem(link, collectionId: collectionId),
            )),
        ],
      ],
    );
  }

  Widget _buildLinkItem(LinkItem link, {String? collectionId, bool isUncategorized = false}) {
    final isSelected = _selectedLinkIds.contains(link.id);
    
    return Draggable<LinkItem>(
      data: link,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            link.title ?? 'Untitled Link',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildLinkCard(link, isSelected, collectionId, isUncategorized),
      ),
      child: _buildLinkCard(link, isSelected, collectionId, isUncategorized),
    );
  }

  Widget _buildLinkCard(LinkItem link, bool isSelected, String? collectionId, bool isUncategorized) {
    return Card(
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: ListTile(
        leading: _isMultiSelectMode
            ? Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedLinkIds.add(link.id!);
                    } else {
                      _selectedLinkIds.remove(link.id!);
                    }
                  });
                },
              )
            : Icon(
                Icons.link,
                color: Theme.of(context).colorScheme.primary,
              ),
        title: Text(
          link.title ?? 'Untitled Link',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          link.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: _isMultiSelectMode
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedLinkIds.remove(link.id!);
                  } else {
                    _selectedLinkIds.add(link.id!);
                  }
                });
              }
            : () => widget.onLinkTap(link),
        onLongPress: () {
          if (!_isMultiSelectMode) {
            setState(() {
              _isMultiSelectMode = true;
              _selectedLinkIds.add(link.id!);
            });
          }
        },
        trailing: _isMultiSelectMode
            ? null
            : PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) => _handleLinkAction(value, link),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      leading: Icon(Icons.copy),
                      title: Text('Copy URL'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_move),
                      title: Text('Move to Collection'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (!isUncategorized)
                    const PopupMenuItem(
                      value: 'uncategorize',
                      child: ListTile(
                        leading: Icon(Icons.remove_circle_outline),
                        title: Text('Remove from Collection'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildUncategorizedSection() {
    return DragTarget<LinkItem>(
      onAcceptWithDetails: (details) {
        final link = details.data;
        widget.onLinkMoved(link, null); // null means uncategorized
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: isDragOver
              ? BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_open,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Uncategorized (${widget.uncategorizedLinks.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isDragOver)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Drop here to remove from collection',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ...widget.uncategorizedLinks.take(_uncategorizedLinksShown).map(
                (link) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: _buildLinkItem(link, isUncategorized: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddCollectionButton() {
    return ElevatedButton.icon(
      onPressed: widget.onCreateCollection,
      icon: const Icon(Icons.add),
      label: const Text('Add Collection'),
    );
  }

  Widget _buildMultiSelectToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedLinkIds.length} selected',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() {
              _selectedLinkIds.clear();
              _isMultiSelectMode = false;
            }),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkOperationsBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedLinkIds.length} links selected',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: () {
              if (widget.onBulkOperation != null) {
                widget.onBulkOperation!(_getSelectedLinks());
              }
            },
            icon: const Icon(Icons.more_horiz),
            label: const Text('Actions'),
          ),
        ],
      ),
    );
  }

  void _toggleCollection(String collectionId) {
    setState(() {
      if (_expandedCollections.contains(collectionId)) {
        _expandedCollections.remove(collectionId);
      } else {
        _expandedCollections.add(collectionId);
        // Load links when expanding if not already loaded
        if (!_collectionLinks.containsKey(collectionId)) {
          _loadCollectionLinks(collectionId);
        }
      }
    });
  }

  Future<void> _loadCollectionLinks(String collectionId, {bool loadMore = false}) async {
    if (_loadingCollections[collectionId] == true) return;

    setState(() {
      _loadingCollections[collectionId] = true;
    });

    try {
      final currentPage = _loadedPages[collectionId] ?? 0;
      final offset = loadMore ? currentPage * _linksPerPage : 0;
      
      // Find the collection by ID to get its name
      final collection = widget.collections.firstWhere(
        (c) => (c.remoteId ?? 'local_${c.id}') == collectionId,
      );
      
      // Get links with pagination using collection name
      final links = await _collectionService.getCollectionLinks(
        collection.name, 
        limit: _linksPerPage,
        offset: offset,
      );
      
      setState(() {
        if (loadMore && _collectionLinks.containsKey(collectionId)) {
          // Append to existing links
          _collectionLinks[collectionId]!.addAll(links);
        } else {
          // Replace existing links
          _collectionLinks[collectionId] = links;
        }
        
        // Update pagination state
        _hasMoreLinks[collectionId] = links.length == _linksPerPage;
        _loadedPages[collectionId] = loadMore ? currentPage + 1 : 1;
        _loadingCollections[collectionId] = false;
      });
    } catch (e) {
      setState(() {
        _loadingCollections[collectionId] = false;
      });
    }
  }

  void _handleLinkAction(String action, LinkItem link) {
    switch (action) {
      case 'edit':
        widget.onLinkEdit(link);
        break;
      case 'copy':
        widget.onLinkCopy(link);
        break;
      case 'move':
        _showMoveToCollectionDialog(link);
        break;
      case 'uncategorize':
        widget.onLinkMoved(link, null); // Move to uncategorized
        break;
      case 'delete':
        widget.onLinkDelete(link);
        break;
    }
  }

  void _handleCollectionAction(String action, Collection collection) {
    switch (action) {
      case 'edit':
        widget.onCollectionEdit(collection);
        break;
      case 'delete':
        widget.onCollectionDelete(collection);
        break;
    }
  }

  void _showMoveToCollectionDialog(LinkItem link) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Uncategorized'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onLinkMoved(link, null);
              },
            ),
            const Divider(),
            ...widget.collections.map((collection) => ListTile(
              leading: const Icon(Icons.folder),
              title: Text(collection.name),
              onTap: () {
                Navigator.of(context).pop();
                widget.onLinkMoved(link, collection.name);
              },
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Clear cache for a specific collection and reload its links if expanded
  void refreshCollection(Collection collection) {
    final collectionKey = collection.remoteId ?? 'local_${collection.id}';
    
    // Clear cache for this collection
    setState(() {
      _collectionLinks.remove(collectionKey);
      _loadingCollections.remove(collectionKey);
      _hasMoreLinks.remove(collectionKey);
      _loadedPages.remove(collectionKey);
    });
    
    // If the collection is currently expanded, reload its links immediately
    if (_expandedCollections.contains(collectionKey)) {
      _loadCollectionLinks(collectionKey);
    }
  }

  /// Clear all collection caches
  void clearAllCaches() {
    setState(() {
      _collectionLinks.clear();
      _loadingCollections.clear();
      _hasMoreLinks.clear();
      _loadedPages.clear();
    });
  }

  List<LinkItem> _getSelectedLinks() {
    final selectedLinks = <LinkItem>[];
    
    // Get selected links from collections
    for (final collection in widget.collections) {
      final links = _collectionLinks[collection.id.toString()] ?? [];
      selectedLinks.addAll(links.where((link) => _selectedLinkIds.contains(link.id)));
    }
    
    // Get selected uncategorized links
    selectedLinks.addAll(widget.uncategorizedLinks.where((link) => _selectedLinkIds.contains(link.id)));
    
    return selectedLinks;
  }
}
