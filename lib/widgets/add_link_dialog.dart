import 'package:flutter/material.dart';
import '../utils/security_utils.dart';

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
  bool _isPrivate = false;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _autoFillFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isValidatingUrl = true);

    // Try to auto-fill title from URL
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && _titleController.text.isEmpty) {
        // Extract domain as fallback title
        final domain = uri.host.replaceAll('www.', '');
        _titleController.text = domain;
      }
    } catch (e) {
      // Invalid URL, will be caught by validator
    }

    setState(() => _isValidatingUrl = false);
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
                          prefixIcon: const Icon(Icons.link),
                          suffixIcon:
                              _isValidatingUrl
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
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

                      // Title Field
                      TextFormField(
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
