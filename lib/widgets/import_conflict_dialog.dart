import 'package:flutter/material.dart';
import 'custom_radio_tile.dart';

class ImportConflictDialog extends StatefulWidget {
  final List<String> conflictingCollections;
  final Function(Map<String, String> resolutions) onResolved;

  const ImportConflictDialog({
    super.key,
    required this.conflictingCollections,
    required this.onResolved,
  });

  @override
  State<ImportConflictDialog> createState() => _ImportConflictDialogState();
}

class _ImportConflictDialogState extends State<ImportConflictDialog> {
  final Map<String, String> _resolutions = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final collection in widget.conflictingCollections) {
      _resolutions[collection] = 'merge'; // Default to merge
      _controllers[collection] = TextEditingController(text: '${collection}_imported');
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Collection Name Conflicts'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following collections already exist. Choose how to handle each conflict:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.conflictingCollections.length,
                itemBuilder: (context, index) {
                  final collection = widget.conflictingCollections[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          CustomRadioTile<String>(
                            value: 'merge',
                            groupValue: _resolutions[collection],
                            onChanged: (value) {
                              setState(() {
                                _resolutions[collection] = value!;
                              });
                            },
                            title: const Text('Merge with existing collection'),
                            subtitle: const Text('Add imported links to the existing collection'),
                            dense: true,
                          ),
                          CustomRadioTile<String>(
                            value: 'rename',
                            groupValue: _resolutions[collection],
                            onChanged: (value) {
                              setState(() {
                                _resolutions[collection] = value!;
                              });
                            },
                            title: const Text('Create with new name'),
                            subtitle: const Text('Create a new collection with a different name'),
                            dense: true,
                          ),
                          if (_resolutions[collection] == 'rename') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _controllers[collection],
                              decoration: const InputDecoration(
                                labelText: 'New collection name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                // Validate name in real-time if needed
                              },
                            ),
                          ],
                          CustomRadioTile<String>(
                            value: 'skip',
                            groupValue: _resolutions[collection],
                            onChanged: (value) {
                              setState(() {
                                _resolutions[collection] = value!;
                              });
                            },
                            title: const Text('Skip collection'),
                            subtitle: const Text('Import links without assigning to any collection'),
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _handleResolve,
          child: const Text('Continue Import'),
        ),
      ],
    );
  }

  void _handleResolve() {
    final resolutions = <String, String>{};
    
    for (final collection in widget.conflictingCollections) {
      final resolution = _resolutions[collection]!;
      
      if (resolution == 'merge') {
        // Keep original name to merge with existing
        resolutions[collection] = collection;
      } else if (resolution == 'rename') {
        // Use new name from text field
        final newName = _controllers[collection]!.text.trim();
        if (newName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please provide a new name for "$collection"'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        resolutions[collection] = newName;
      } else if (resolution == 'skip') {
        // Use empty string to indicate no collection assignment
        resolutions[collection] = '';
      }
    }
    
    Navigator.of(context).pop();
    widget.onResolved(resolutions);
  }
}
