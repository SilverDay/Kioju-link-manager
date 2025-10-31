import 'package:flutter/material.dart';
import '../models/collection.dart';
import '../models/link.dart';
import '../services/link_service.dart';
import '../services/sync_strategy.dart';
import '../services/sync_settings.dart';
import 'custom_radio_tile.dart';

class BulkOperationsDialog extends StatefulWidget {
  final List<LinkItem> selectedLinks;
  final List<Collection> collections;
  final Function() onOperationComplete;

  const BulkOperationsDialog({
    super.key,
    required this.selectedLinks,
    required this.collections,
    required this.onOperationComplete,
  });

  @override
  State<BulkOperationsDialog> createState() => _BulkOperationsDialogState();
}

class _BulkOperationsDialogState extends State<BulkOperationsDialog> {

  final LinkService _linkService = LinkService.instance;
  bool _isProcessing = false;
  String? _selectedOperation;
  Collection? _targetCollection;
  double _progress = 0.0;
  String _progressText = '';
  List<String> _errors = [];
  int _successCount = 0;
  int _failedCount = 0;
  bool _isImmediateSync = false;

  @override
  void initState() {
    super.initState();
    _loadSyncSettings();
  }

  Future<void> _loadSyncSettings() async {
    final isImmediate = await SyncSettings.isImmediateSyncEnabled();
    setState(() {
      _isImmediateSync = isImmediate;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Bulk Operations (${widget.selectedLinks.length} links)'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose an operation to perform on the selected links:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            
            // Operation selection
            CustomRadioTile<String>(
              value: 'move',
              groupValue: _selectedOperation,
              onChanged: (value) {
                setState(() {
                  _selectedOperation = value;
                });
              },
              title: const Text('Move to Collection'),
              subtitle: const Text('Move all selected links to a specific collection'),
            ),
            
            CustomRadioTile<String>(
              value: 'uncategorize',
              groupValue: _selectedOperation,
              onChanged: (value) {
                setState(() {
                  _selectedOperation = value;
                  _targetCollection = null; // Clear target collection
                });
              },
              title: const Text('Remove from Collections'),
              subtitle: const Text('Move all selected links to uncategorized'),
            ),
            
            CustomRadioTile<String>(
              value: 'delete',
              groupValue: _selectedOperation,
              onChanged: (value) {
                setState(() {
                  _selectedOperation = value;
                  _targetCollection = null; // Clear target collection
                });
              },
              title: const Text('Delete Links'),
              subtitle: const Text('Permanently delete all selected links'),
            ),

            // Collection selection for move operation
            if (_selectedOperation == 'move') ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Select target collection:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: widget.collections.length,
                  itemBuilder: (context, index) {
                    final collection = widget.collections[index];
                    return CustomRadioTile<Collection>(
                      value: collection,
                      groupValue: _targetCollection,
                      onChanged: (value) {
                        setState(() {
                          _targetCollection = value;
                        });
                      },
                      title: Text(collection.name),
                      subtitle: Text('${collection.linkCount} links'),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    );
                  },
                ),
              ),
            ],

            // Warning for delete operation
            if (_selectedOperation == 'delete') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone. All selected links will be permanently deleted.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Sync mode indicator
            if (!_isProcessing) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isImmediateSync 
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isImmediateSync ? Icons.sync : Icons.sync_disabled,
                      color: _isImmediateSync 
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isImmediateSync
                            ? 'Changes will be synced to server immediately'
                            : 'Changes will be saved locally and synced manually',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _isImmediateSync 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Progress indicator during processing
            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _progressText,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (_isImmediateSync)
                        Icon(
                          Icons.cloud_sync,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(_progress * 100).round()}% complete',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_successCount > 0 || _failedCount > 0)
                        Text(
                          'Success: $_successCount, Failed: $_failedCount',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (_errors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Errors (${_errors.length}):',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...(_errors.take(3).map((error) => Text(
                            '• $error',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ))),
                          if (_errors.length > 3)
                            Text(
                              '... and ${_errors.length - 3} more',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isProcessing ? null : _performOperation,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Execute'),
        ),
      ],
    );
  }

  Future<void> _performOperation() async {
    if (_selectedOperation == null) return;
    
    if (_selectedOperation == 'move' && _targetCollection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a target collection'),
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _progressText = 'Starting operation...';
      _errors = [];
      _successCount = 0;
      _failedCount = 0;
    });

    try {
      final totalLinks = widget.selectedLinks.length;
      
      switch (_selectedOperation) {
        case 'move':
          if (_targetCollection != null) {
            await _performBulkMove(_targetCollection!.name, totalLinks);
          }
          break;
        case 'uncategorize':
          await _performBulkMove(null, totalLinks);
          break;
        case 'delete':
          await _performBulkDelete(totalLinks);
          break;
      }

      if (mounted) {
        widget.onOperationComplete();
        
        // Show comprehensive completion message
        final operationName = _selectedOperation == 'move' 
            ? 'moved to ${_targetCollection?.name}'
            : _selectedOperation == 'uncategorize' 
                ? 'removed from collections'
                : 'deleted';
        
        String message;
        Color? backgroundColor;
        
        if (_errors.isEmpty) {
          // Complete success
          message = '$_successCount links $operationName successfully';
          if (_isImmediateSync) {
            message += ' and synced to server';
          } else {
            message += '. Use sync to upload changes.';
          }
          backgroundColor = Theme.of(context).colorScheme.primary;
        } else if (_successCount > 0) {
          // Partial success
          message = '$_successCount links $operationName successfully, $_failedCount failed';
          if (_isImmediateSync) {
            message += '. Failed items marked for manual sync.';
          }
          backgroundColor = Theme.of(context).colorScheme.tertiary;
        } else {
          // Complete failure
          message = 'Operation failed: ${_errors.first}';
          backgroundColor = Theme.of(context).colorScheme.error;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: Duration(seconds: _errors.isEmpty ? 3 : 6),
          ),
        );
        
        // Close dialog after a brief delay to show final progress
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operation failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _performBulkMove(String? targetCollection, int totalLinks) async {
    final linkIds = widget.selectedLinks.map((link) => link.id!).toList();
    
    try {
      final result = await _linkService.moveLinksBulk(
        linkIds: linkIds,
        toCollection: targetCollection,
        onProgress: (completed, total) {
          setState(() {
            _progress = completed / total;
            _progressText = _isImmediateSync 
                ? 'Moving and syncing link $completed of $total...'
                : 'Moving link $completed of $total...';
          });
        },
      );
      
      _handleBulkOperationResult(result, totalLinks, 'move');
    } catch (e) {
      _errors.add('Bulk move operation failed: ${e.toString()}');
      _failedCount = totalLinks;
    }
    
    setState(() {
      _progress = 1.0;
      _progressText = _generateCompletionText();
    });
  }

  Future<void> _performBulkDelete(int totalLinks) async {
    final linkIds = widget.selectedLinks.map((link) => link.id!).toList();
    
    try {
      final result = await _linkService.deleteLinksBulk(
        linkIds: linkIds,
        onProgress: (completed, total) {
          setState(() {
            _progress = completed / total;
            _progressText = _isImmediateSync 
                ? 'Deleting and syncing link $completed of $total...'
                : 'Deleting link $completed of $total...';
          });
        },
      );
      
      _handleBulkOperationResult(result, totalLinks, 'delete');
    } catch (e) {
      _errors.add('Bulk delete operation failed: ${e.toString()}');
      _failedCount = totalLinks;
    }
    
    setState(() {
      _progress = 1.0;
      _progressText = _generateCompletionText();
    });
  }

  /// Handles the result of a bulk operation and updates counters
  void _handleBulkOperationResult(SyncResult result, int totalLinks, String operationType) {
    switch (result.type) {
      case SyncResultType.immediateSuccess:
      case SyncResultType.manualQueued:
        _successCount = totalLinks;
        break;
      case SyncResultType.immediatePartialFailure:
        _successCount = totalLinks - result.failedItemIds.length;
        _failedCount = result.failedItemIds.length;
        _errors.add(result.errorMessage ?? 'Some $operationType operations failed');
        break;
      case SyncResultType.immediateFailure:
        _failedCount = totalLinks;
        _errors.add(result.errorMessage ?? 'Bulk $operationType operation failed');
        break;
    }
  }

  /// Generates completion text based on operation results
  String _generateCompletionText() {
    if (_errors.isEmpty) {
      return _isImmediateSync 
          ? 'Operation completed and synced successfully'
          : 'Operation completed locally';
    } else if (_successCount > 0) {
      return _isImmediateSync
          ? 'Operation completed with partial sync failures'
          : 'Operation completed with some failures';
    } else {
      return 'Operation failed';
    }
  }
}
