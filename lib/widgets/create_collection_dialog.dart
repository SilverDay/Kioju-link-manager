import 'package:flutter/material.dart';
import 'custom_radio_tile.dart';

class CreateCollectionDialog extends StatefulWidget {
  const CreateCollectionDialog({super.key});

  @override
  State<CreateCollectionDialog> createState() => _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<CreateCollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _visibility = 'public';
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.create_new_folder, color: Colors.blue),
          SizedBox(width: 12),
          Text('Create New Collection'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Collection Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Collection Name *',
                  hintText: 'Enter a name for your collection',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder),
                ),
                maxLength: 100,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Collection name is required';
                  }
                  if (value.trim().length < 2) {
                    return 'Collection name must be at least 2 characters';
                  }
                  return null;
                },
                enabled: !_isCreating,
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Describe what this collection contains',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                maxLength: 2000,
                enabled: !_isCreating,
              ),
              const SizedBox(height: 16),

              // Visibility
              Text(
                'Visibility',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  CustomRadioTile<String>(
                    value: 'public',
                    groupValue: _visibility,
                    onChanged: _isCreating ? null : (value) {
                      setState(() {
                        _visibility = value!;
                      });
                    },
                    title: const Text('Public'),
                    subtitle: const Text('Visible to everyone'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CustomRadioTile<String>(
                    value: 'private',
                    groupValue: _visibility,
                    onChanged: _isCreating ? null : (value) {
                      setState(() {
                        _visibility = value!;
                      });
                    },
                    title: const Text('Private'),
                    subtitle: const Text('Only visible to you'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CustomRadioTile<String>(
                    value: 'hidden',
                    groupValue: _visibility,
                    onChanged: _isCreating ? null : (value) {
                      setState(() {
                        _visibility = value!;
                      });
                    },
                    title: const Text('Hidden'),
                    subtitle: const Text('Hidden from public listings'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createCollection,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Collection'),
        ),
      ],
    );
  }

  Future<void> _createCollection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final result = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        'visibility': _visibility,
      };

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create collection: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

Future<Map<String, dynamic>?> showCreateCollectionDialog(BuildContext context) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => const CreateCollectionDialog(),
  );
}
