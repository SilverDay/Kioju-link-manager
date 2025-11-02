import 'package:flutter/material.dart';
import '../utils/bookmark_import.dart';
import '../services/import_service.dart';

class ImportSummaryDialog extends StatelessWidget {
  final ImportResult importResult;
  final int linksImported;
  final ImportSyncResult? syncResult;

  const ImportSummaryDialog({
    super.key,
    required this.importResult,
    required this.linksImported,
    this.syncResult,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Complete'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryItem(
              context,
              Icons.link,
              'Links imported',
              linksImported.toString(),
              Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildSummaryItem(
              context,
              Icons.folder_outlined,
              'Collections created',
              importResult.collectionsCreated.length.toString(),
              Colors.green,
            ),
            if (importResult.collectionsCreated.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New collections:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...importResult.collectionsCreated.map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Text(
                          '• $name',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (importResult.conflictResolutions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildSummaryItem(
                context,
                Icons.merge_type,
                'Collection conflicts resolved',
                importResult.conflictResolutions.length.toString(),
                Colors.orange,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conflict resolutions:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...importResult.conflictResolutions.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Text(
                          entry.value.isEmpty
                              ? '• ${entry.key} → Uncategorized'
                              : '• ${entry.key} → ${entry.value}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Sync status section
            if (syncResult != null) ...[
              const SizedBox(height: 12),
              _buildSyncStatusSection(context, syncResult!),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      syncResult?.isImmediateSync == true
                          ? 'Your links have been imported and synced to the server. '
                              'You can manage collections and move links between them using the folder view.'
                          : 'Your links have been imported locally. '
                              'Use the sync button to upload them to the server when ready.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSyncStatusSection(
    BuildContext context,
    ImportSyncResult syncResult,
  ) {
    final statusColor =
        syncResult.isCompleteSuccess
            ? Colors.green
            : syncResult.hasPartialFailures
            ? Colors.orange
            : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              syncResult.isImmediateSync ? Icons.sync : Icons.save,
              size: 20,
              color: statusColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                syncResult.isImmediateSync ? 'Sync Status' : 'Save Status',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                syncResult.statusMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (syncResult.isImmediateSync) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildSyncStat(
                        context,
                        'Synced',
                        syncResult.linksSuccessfullySynced.toString(),
                        Colors.green,
                      ),
                    ),
                    if (syncResult.linksMarkedForSync > 0) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSyncStat(
                          context,
                          'Queued',
                          syncResult.linksMarkedForSync.toString(),
                          Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (syncResult.linksMarkedForSync > 0) ...[
                const SizedBox(height: 8),
                _buildSyncStat(
                  context,
                  'Saved locally',
                  syncResult.linksMarkedForSync.toString(),
                  Colors.blue,
                ),
              ],
              if (syncResult.syncErrors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Errors: ${syncResult.syncErrors.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncStat(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
