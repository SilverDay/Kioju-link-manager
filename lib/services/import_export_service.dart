import 'dart:io';
import 'package:file_selector/file_selector.dart';
import '../services/app_settings.dart';
import '../services/sync_settings.dart';
import '../models/link.dart';
import '../utils/bookmark_export.dart';

/// Service for handling enhanced import/export operations with user preferences
class ImportExportService {
  static const ImportExportService _instance = ImportExportService._internal();
  factory ImportExportService() => _instance;
  const ImportExportService._internal();

  /// Determines the sync strategy to use for import operations
  /// based on user preferences
  Future<bool> shouldUseImmediateSyncForImport() async {
    final importSyncMode = await AppSettings.getImportSyncMode();

    switch (importSyncMode) {
      case 'immediate':
        return true;
      case 'manual':
        return false;
      case 'follow_global':
      default:
        return await SyncSettings.isImmediateSyncEnabled();
    }
  }

  /// Exports links to browser bookmarks with enhanced auto-save functionality
  Future<ExportResult> exportToBrowser(List<LinkItem> links) async {
    return exportToBrowserWithPreferredPath(links, null);
  }

  /// Exports links directly to the specified file (for "Export" button)
  Future<ExportResult> exportToLoadedFile(
    List<LinkItem> links,
    String filePath,
  ) async {
    try {
      if (!await File(filePath).exists()) {
        return ExportResult.error('File does not exist: $filePath');
      }

      // Read existing file and merge with Kioju links
      final existingHtml = await File(filePath).readAsString();
      final mergedHtml = mergeWithExistingBookmarks(links, existingHtml);
      await File(filePath).writeAsString(mergedHtml);

      return ExportResult.success(
        path: filePath,
        linkCount: links.length,
        isAutoSaved: false, // This is a direct export, not auto-save
      );
    } catch (e) {
      return ExportResult.error(e.toString());
    }
  }

  /// Exports links to browser bookmarks with a preferred file path
  Future<ExportResult> exportToBrowserWithPreferredPath(
    List<LinkItem> links,
    String? preferredPath,
  ) async {
    try {
      final autoSave = await AppSettings.getAutoSaveExport();
      final lastPath = await AppSettings.getLastExportPath();

      // Only auto-save if the setting is enabled
      String? targetPath;
      bool isAutoSaved = false;

      if (autoSave) {
        // Priority: 1) preferredPath (currently loaded file), 2) lastPath
        if (preferredPath != null && await File(preferredPath).exists()) {
          targetPath = preferredPath;
          isAutoSaved = true;
        } else if (lastPath != null && await File(lastPath).exists()) {
          targetPath = lastPath;
          isAutoSaved = true;
        }
      }

      if (targetPath != null) {
        // Read existing file and merge with Kioju links
        final existingHtml = await File(targetPath).readAsString();
        final mergedHtml = mergeWithExistingBookmarks(links, existingHtml);
        await File(targetPath).writeAsString(mergedHtml);
        return ExportResult.success(
          path: targetPath,
          linkCount: links.length,
          isAutoSaved: isAutoSaved,
        );
      } else {
        // Ask user for save location
        final suggestedName =
            preferredPath != null
                ? preferredPath.split('/').last.split('\\').last
                : 'bookmarks.html';
        final file = await getSaveLocation(suggestedName: suggestedName);
        if (file != null) {
          // Check if user chose the same file as currently loaded (merge) or new file (replace)
          final shouldMerge =
              preferredPath != null && file.path == preferredPath;

          if (shouldMerge) {
            // Merge with existing bookmarks
            final existingHtml = await File(file.path).readAsString();
            final mergedHtml = mergeWithExistingBookmarks(links, existingHtml);
            await File(file.path).writeAsString(mergedHtml);
          } else {
            // Create new file with just Kioju links
            final html = exportToNetscapeHtml(links);
            await File(file.path).writeAsString(html);
          }

          // Remember this path for future auto-saves
          await AppSettings.setLastExportPath(file.path);

          return ExportResult.success(
            path: file.path,
            linkCount: links.length,
            isAutoSaved: false,
          );
        } else {
          return ExportResult.cancelled();
        }
      }
    } catch (e) {
      return ExportResult.error(e.toString());
    }
  }

  /// Imports links with respect to user's import sync preferences
  Future<ImportSyncResult> importWithSyncPreference(
    List<LinkItem> links,
  ) async {
    final useImmediateSync = await shouldUseImmediateSyncForImport();
    final errors = <String>[];
    final successful = <LinkItem>[];

    for (final link in links) {
      try {
        // Create the sync operation based on preference
        if (useImmediateSync) {
          // Use immediate sync strategy
          // Implementation would depend on your sync operation structure
          // This is a simplified example - actual implementation would use SyncStrategyFactory
          successful.add(link);
        } else {
          // Use manual sync - just mark as dirty
          successful.add(link);
        }
      } catch (e) {
        errors.add('${link.url}: ${e.toString()}');
      }
    }

    return ImportSyncResult(
      successful: successful,
      errors: errors,
      syncMode: useImmediateSync ? 'immediate' : 'manual',
    );
  }

  /// Clears the remembered export path (useful when user wants to choose new location)
  Future<void> clearLastExportPath() async {
    await AppSettings.setLastExportPath(null);
  }

  /// Gets the current export settings summary for display
  Future<ExportSettingsSummary> getExportSettingsSummary() async {
    final autoSave = await AppSettings.getAutoSaveExport();
    final lastPath = await AppSettings.getLastExportPath();
    final importSyncMode = await AppSettings.getImportSyncMode();

    return ExportSettingsSummary(
      autoSaveEnabled: autoSave,
      lastExportPath: lastPath,
      importSyncMode: importSyncMode,
      hasValidLastPath: lastPath != null && await File(lastPath).exists(),
    );
  }
}

/// Result of an export operation
class ExportResult {
  final bool success;
  final String? path;
  final int? linkCount;
  final bool isAutoSaved;
  final String? error;

  const ExportResult._({
    required this.success,
    this.path,
    this.linkCount,
    this.isAutoSaved = false,
    this.error,
  });

  factory ExportResult.success({
    required String path,
    required int linkCount,
    required bool isAutoSaved,
  }) {
    return ExportResult._(
      success: true,
      path: path,
      linkCount: linkCount,
      isAutoSaved: isAutoSaved,
    );
  }

  factory ExportResult.cancelled() {
    return const ExportResult._(success: false);
  }

  factory ExportResult.error(String error) {
    return ExportResult._(success: false, error: error);
  }

  String get message {
    if (!success) {
      return error ?? 'Export cancelled';
    }

    final autoText = isAutoSaved ? ' (auto-saved)' : '';
    return 'Successfully exported $linkCount links$autoText';
  }
}

/// Result of an import operation with sync information
class ImportSyncResult {
  final List<LinkItem> successful;
  final List<String> errors;
  final String syncMode;

  const ImportSyncResult({
    required this.successful,
    required this.errors,
    required this.syncMode,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get successCount => successful.length;
  int get errorCount => errors.length;
}

/// Summary of current export settings
class ExportSettingsSummary {
  final bool autoSaveEnabled;
  final String? lastExportPath;
  final String importSyncMode;
  final bool hasValidLastPath;

  const ExportSettingsSummary({
    required this.autoSaveEnabled,
    required this.lastExportPath,
    required this.importSyncMode,
    required this.hasValidLastPath,
  });

  String get importSyncDescription {
    switch (importSyncMode) {
      case 'immediate':
        return 'Always sync imports immediately';
      case 'manual':
        return 'Always queue imports for manual sync';
      case 'follow_global':
      default:
        return 'Follow global sync setting';
    }
  }

  String get exportDescription {
    if (autoSaveEnabled && hasValidLastPath) {
      return 'Auto-save to: ${lastExportPath!.split('/').last}';
    } else if (autoSaveEnabled) {
      return 'Auto-save enabled (no file selected yet)';
    } else {
      return 'Always ask where to save';
    }
  }
}
