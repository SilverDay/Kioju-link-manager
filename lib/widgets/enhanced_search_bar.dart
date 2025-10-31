import 'package:flutter/material.dart';
import '../models/collection.dart';

class EnhancedSearchBar extends StatefulWidget {
  final TextEditingController searchController;
  final List<Collection> collections;
  final Collection? selectedCollection;
  final Function(String) onSearchChanged;
  final Function(Collection?) onCollectionChanged;
  final bool showCollectionFilter;

  const EnhancedSearchBar({
    super.key,
    required this.searchController,
    required this.collections,
    required this.onSearchChanged,
    required this.onCollectionChanged,
    this.selectedCollection,
    this.showCollectionFilter = true,
  });

  @override
  State<EnhancedSearchBar> createState() => _EnhancedSearchBarState();
}

class _EnhancedSearchBarState extends State<EnhancedSearchBar> {
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Main search bar
          TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.search,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              hintText: widget.selectedCollection != null
                  ? 'Search in "${widget.selectedCollection!.name}"...'
                  : 'Search links...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              suffixIcon: widget.showCollectionFilter
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.selectedCollection != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => widget.onCollectionChanged(null),
                            tooltip: 'Clear collection filter',
                          ),
                        IconButton(
                          icon: Icon(
                            _showFilters ? Icons.filter_list : Icons.tune,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _showFilters = !_showFilters;
                            });
                          },
                          tooltip: 'Filter options',
                        ),
                      ],
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            onChanged: widget.onSearchChanged,
          ),

          // Collection filter section
          if (_showFilters && widget.showCollectionFilter) ...[
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter by Collection',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // All collections chip
                      FilterChip(
                        label: const Text('All Collections'),
                        selected: widget.selectedCollection == null,
                        onSelected: (selected) {
                          if (selected) {
                            widget.onCollectionChanged(null);
                          }
                        },
                        avatar: widget.selectedCollection == null
                            ? const Icon(Icons.check, size: 16)
                            : const Icon(Icons.folder_outlined, size: 16),
                      ),
                      // Uncategorized chip
                      FilterChip(
                        label: const Text('Uncategorized'),
                        selected: widget.selectedCollection?.name == '_uncategorized',
                        onSelected: (selected) {
                          if (selected) {
                            // Create a special collection object for uncategorized
                            final uncategorized = Collection(
                              id: -1,
                              name: '_uncategorized',
                              linkCount: 0,
                            );
                            widget.onCollectionChanged(uncategorized);
                          }
                        },
                        avatar: widget.selectedCollection?.name == '_uncategorized'
                            ? const Icon(Icons.check, size: 16)
                            : const Icon(Icons.folder_open_outlined, size: 16),
                      ),
                      // Individual collection chips
                      ...widget.collections.map(
                        (collection) => FilterChip(
                          label: Text(collection.name),
                          selected: widget.selectedCollection?.id == collection.id,
                          onSelected: (selected) {
                            widget.onCollectionChanged(selected ? collection : null);
                          },
                          avatar: widget.selectedCollection?.id == collection.id
                              ? const Icon(Icons.check, size: 16)
                              : const Icon(Icons.folder, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Active filter indicator
          if (widget.selectedCollection != null) ...[
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.selectedCollection!.name == '_uncategorized'
                        ? 'Showing uncategorized links'
                        : 'Showing links in "${widget.selectedCollection!.name}"',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => widget.onCollectionChanged(null),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
