import 'package:flutter/material.dart';

class SyncConflictDialog extends StatelessWidget {
  final int unsyncedCollections;
  final int unsyncedLinks;

  const SyncConflictDialog({
    super.key,
    required this.unsyncedCollections,
    required this.unsyncedLinks,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          const Text('Sync Conflict Warning'),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          'You have unsynced local changes',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Syncing down from the server may overwrite your local modifications. '
                          'We recommend syncing up your changes first to avoid data loss.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Unsynced changes summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unsynced Changes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (unsyncedCollections > 0) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$unsyncedCollections collection${unsyncedCollections == 1 ? '' : 's'} modified',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (unsyncedLinks > 0) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.link,
                          size: 20,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$unsyncedLinks link${unsyncedLinks == 1 ? '' : 's'} modified',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Explanation of options
            Text(
              'What would you like to do?',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            _buildOptionCard(
              context,
              icon: Icons.cloud_upload,
              iconColor: Colors.green,
              title: 'Sync Up First (Recommended)',
              description:
                  'Upload your local changes to the server, then sync down safely',
            ),
            const SizedBox(height: 8),

            _buildOptionCard(
              context,
              icon: Icons.cloud_download,
              iconColor: Colors.orange,
              title: 'Continue Anyway',
              description:
                  'Download server changes and potentially lose local modifications',
            ),
            const SizedBox(height: 8),

            _buildOptionCard(
              context,
              icon: Icons.cancel,
              iconColor: Colors.grey,
              title: 'Cancel',
              description: 'Go back and review your changes manually',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('continue'),
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
          child: const Text('Continue Anyway'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop('sync_up_first'),
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Sync Up First'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> showSyncConflictDialog(
  BuildContext context, {
  required int unsyncedCollections,
  required int unsyncedLinks,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false, // Force user to make a choice
    builder:
        (context) => SyncConflictDialog(
          unsyncedCollections: unsyncedCollections,
          unsyncedLinks: unsyncedLinks,
        ),
  );
}
