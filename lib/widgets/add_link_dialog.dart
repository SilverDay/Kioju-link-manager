import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/security_utils.dart';
import '../services/web_metadata_service.dart';
import '../services/app_settings.dart';
import '../models/link.dart';

class AddLinkDialog extends StatefulWidget {
  const AddLinkDialog({super.key});

  @override
  State<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<AddLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _isValidatingUrl = false;
  bool _isPrivate = true; // Default to private as per API documentation
  bool _autoFetchEnabled = true;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadAutoFetchSetting();
  }

  Future<void> _loadAutoFetchSetting() async {
    final enabled = await AppSettings.getAutoFetchMetadata();
    if (mounted) {
      setState(() {
        _autoFetchEnabled = enabled;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _urlController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _autoFillFromUrl() async {
    // Cancel any existing timer
    _debounceTimer?.cancel();

    // Start a new timer with 1 second delay
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _performAutoFill();
    });
  }

  Future<void> _performAutoFill() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Check if auto-fetch is enabled
    final autoFetchEnabled = await AppSettings.getAutoFetchMetadata();
    if (!autoFetchEnabled) return;

    setState(() => _isValidatingUrl = true);

    try {
      // Fetch metadata from the URL
      final metadata = await WebMetadataService.fetchMetadata(url);

      if (metadata != null && mounted) {
        setState(() {
          // Auto-fill title if empty and metadata has title
          if (_titleController.text.isEmpty && metadata.title != null) {
            _titleController.text = metadata.title!;
          }

          // Auto-fill description if empty and metadata has description
          if (_descriptionController.text.isEmpty &&
              metadata.description != null) {
            _descriptionController.text = metadata.description!;
          }
        });
      } else {
        // Fallback to domain extraction if metadata fetch failed
        final uri = Uri.tryParse(url);
        if (uri != null &&
            uri.hasScheme &&
            _titleController.text.isEmpty &&
            mounted) {
          setState(() {
            final domain = uri.host.replaceAll('www.', '');
            _titleController.text = domain;
          });
        }
      }
    } catch (e) {
      // Fallback to domain extraction on any error
      try {
        final uri = Uri.parse(url);
        if (uri.hasScheme && _titleController.text.isEmpty && mounted) {
          setState(() {
            final domain = uri.host.replaceAll('www.', '');
            _titleController.text = domain;
          });
        }
      } catch (e) {
        // Invalid URL, will be caught by validator
      }
    }

    if (mounted) {
      setState(() => _isValidatingUrl = false);
    }
  }

  String? _validateUrlField(String? value) {
    final validation = SecurityUtils.validateUrl(value);
    return validation.isValid ? null : validation.message;
  }

  bool _isUrlValid(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.hasScheme && uri.scheme.startsWith('http');
    } catch (e) {
      return false;
    }
  }

  List<String> _parseTagsInput(String input) {
    return input
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.add_link,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add New Link',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // URL Field
                      TextFormField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          labelText: 'URL *',
                          hintText: 'https://example.com',
                          helperText:
                              _autoFetchEnabled
                                  ? 'Title and description will be fetched automatically'
                                  : 'Auto-fetch is disabled in settings',
                          prefixIcon: const Icon(Icons.link),
                          suffixIcon:
                              _isValidatingUrl
                                  ? Tooltip(
                                    message: 'Fetching page information...',
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      margin: const EdgeInsets.all(12),
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                  : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        ),
                        validator: _validateUrlField,
                        onChanged: (_) => _autoFillFromUrl(),
                        textInputAction: TextInputAction.next,
                      ),

                      const SizedBox(height: 16),

                      // Title Field with refresh button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                labelText: 'Title',
                                hintText: 'Enter a descriptive title',
                                prefixIcon: const Icon(Icons.title),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Refresh page info',
                            child: IconButton(
                              onPressed:
                                  _isValidatingUrl
                                      ? null
                                      : () async {
                                        if (_urlController.text
                                            .trim()
                                            .isNotEmpty) {
                                          await _performAutoFill();
                                        }
                                      },
                              icon:
                                  _isValidatingUrl
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.refresh),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Description Field
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          hintText:
                              'Add a description or notes about this link',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 52),
                            child: Icon(Icons.description),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        ),
                        textInputAction: TextInputAction.next,
                      ),

                      const SizedBox(height: 16),

                      // Tags Field
                      TextFormField(
                        controller: _tagsController,
                        decoration: InputDecoration(
                          labelText: 'Tags',
                          hintText: 'development, flutter, tutorial',
                          prefixIcon: const Icon(Icons.tag),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          helperText: 'Separate multiple tags with commas',
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleSubmit(),
                      ),

                      const SizedBox(height: 16),

                      // Private Checkbox
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Privacy Setting',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Private links are only visible to you',
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
                            Switch(
                              value: _isPrivate,
                              onChanged:
                                  (value) => setState(() => _isPrivate = value),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Preview Section (if URL is valid)
                      if (_urlController.text.isNotEmpty &&
                          _isUrlValid(_urlController.text)) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preview',
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.link,
                                      size: 16,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _titleController.text.isNotEmpty
                                              ? _titleController.text
                                              : 'Untitled Link',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          _urlController.text,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.copyWith(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_parseTagsInput(
                                _tagsController.text,
                              ).isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children:
                                      _parseTagsInput(_tagsController.text)
                                          .map(
                                            (tag) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                tag,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onSecondaryContainer,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Fixed footer with action buttons
            Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _handleSubmit,
                    icon: const Icon(Icons.save),
                    label: const Text('Add Link'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() == true) {
      // Validate all inputs with security utils
      final urlValidation = SecurityUtils.validateUrl(_urlController.text);
      final titleValidation = SecurityUtils.validateTitle(
        _titleController.text,
      );
      final notesValidation = SecurityUtils.validateNotes(
        _descriptionController.text,
      );
      final tagsValidation = SecurityUtils.validateTags(
        _parseTagsInput(_tagsController.text),
      );

      if (!urlValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL: ${urlValidation.message}')),
        );
        return;
      }

      if (!titleValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid title: ${titleValidation.message}')),
        );
        return;
      }

      if (!notesValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid description: ${notesValidation.message}'),
          ),
        );
        return;
      }

      if (!tagsValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid tags: ${tagsValidation.message}')),
        );
        return;
      }

      final result = {
        'url': urlValidation.sanitizedValue,
        'title': titleValidation.sanitizedValue,
        'description': notesValidation.sanitizedValue,
        'tags': tagsValidation.sanitizedValue ?? <String>[],
        'isPrivate': _isPrivate,
      };

      Navigator.of(context).pop(result);
    }
  }
}

// Helper function to show the dialog
Future<Map<String, dynamic>?> showAddLinkDialog(BuildContext context) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => const AddLinkDialog(),
  );
}

class EditLinkDialog extends StatefulWidget {
  final LinkItem item;

  const EditLinkDialog({super.key, required this.item});

  @override
  State<EditLinkDialog> createState() => _EditLinkDialogState();
}

class _EditLinkDialogState extends State<EditLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _isPrivate = true; // Default to private as per API documentation

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    _titleController.text = widget.item.title ?? '';
    _descriptionController.text = widget.item.notes ?? '';
    _tagsController.text = widget.item.tags.join(', ');
    _isPrivate = widget.item.isPrivate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  List<String> _parseTags(String tagsText) {
    return tagsText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  void _saveLink() {
    if (_formKey.currentState!.validate()) {
      // Validate all inputs
      final titleValidation = SecurityUtils.validateTitle(
        _titleController.text.trim(),
      );
      final notesValidation = SecurityUtils.validateNotes(
        _descriptionController.text.trim(),
      );
      final tags = _parseTags(_tagsController.text);
      final tagsValidation = SecurityUtils.validateTags(tags);

      if (!titleValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid title: ${titleValidation.message}')),
        );
        return;
      }

      if (!notesValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid description: ${notesValidation.message}'),
          ),
        );
        return;
      }

      if (!tagsValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid tags: ${tagsValidation.message}')),
        );
        return;
      }

      final result = {
        'url': widget.item.url, // URL cannot be changed through API
        'title': titleValidation.sanitizedValue,
        'description': notesValidation.sanitizedValue,
        'tags': tagsValidation.sanitizedValue ?? <String>[],
        'isPrivate': _isPrivate,
      };

      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Edit Link'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // URL display (read-only)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.item.url,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Title field
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Title is required';
                  }
                  final validation = SecurityUtils.validateTitle(value.trim());
                  if (!validation.isValid) {
                    return validation.message;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description field
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final validation = SecurityUtils.validateNotes(
                      value.trim(),
                    );
                    if (!validation.isValid) {
                      return validation.message;
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Tags field
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                  prefixIcon: Icon(Icons.tag),
                  hintText: 'research, articles, important',
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final tags = _parseTags(value);
                    final validation = SecurityUtils.validateTags(tags);
                    if (!validation.isValid) {
                      return validation.message;
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Privacy toggle
              Row(
                children: [
                  Icon(
                    Icons.visibility,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Private Link',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: _isPrivate,
                    onChanged: (value) {
                      setState(() {
                        _isPrivate = value;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saveLink, child: const Text('Update')),
      ],
    );
  }
}

// Helper function to show the edit dialog
Future<Map<String, dynamic>?> showEditLinkDialog(
  BuildContext context,
  LinkItem item,
) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => EditLinkDialog(item: item),
  );
}
