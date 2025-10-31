import 'package:flutter/material.dart';
import '../models/collection.dart';
import 'custom_radio_tile.dart';

class DeleteCollectionDialog extends StatefulWidget {
  final Collection collection;

  const DeleteCollectionDialog({
    super.key,
    required this.collection,
  });

  @override
  State<DeleteCollectionDialog> createState() => _DeleteCollectionDialogState();
}

class _DeleteCollectionDialogState extends State<DeleteCollectionDialog> {
  String _linkHandling = 'move_links'; // 'move_links' or 'delete_links'
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          const Text('Delete Collection'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This action cannot be undone',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You are about to delete "${widget.collection.name}"',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Collection info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.collection.name,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.collection.description?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.collection.description!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.collection.linkCount} links in this collection',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Link handling options (only show if collection has links)
            if (widget.collection.linkCount > 0) ...[
              const SizedBox(height: 20),
              Text(
                'What should happen to the links in this collection?',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              
              CustomRadioTile<String>(
                value: 'move_links',
                groupValue: _linkHandling,
                onChanged: _isDeleting ? null : (value) {
                  setState(() {
                    _linkHandling = value!;
                  });
                },
                title: const Text('Move to Uncategorized'),
                subtitle: const Text('Keep all links but remove them from this collection'),
                contentPadding: EdgeInsets.zero,
              ),
              
              CustomRadioTile<String>(
                value: 'delete_links',
                groupValue: _linkHandling,
                onChanged: _isDeleting ? null : (value) {
                  setState(() {
                    _linkHandling = value!;
                  });
                },
                title: Text(
                  'Delete All Links',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                subtitle: Text(
                  'Permanently delete all ${widget.collection.linkCount} links in this collection',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isDeleting ? null : _deleteCollection,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Delete Collection'),
        ),
      ],
    );
  }

  Future<void> _deleteCollection() async {
    setState(() {
      _isDeleting = true;
    });

    try {
      final result = {
        'id': widget.collection.remoteId ?? widget.collection.id?.toString(),
        'linkHandling': _linkHandling,
      };

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete collection: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

Future<Map<String, dynamic>?> showDeleteCollectionDialog(
  BuildContext context,
  Collection collection,
) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => DeleteCollectionDialog(collection: collection),
  );
}
