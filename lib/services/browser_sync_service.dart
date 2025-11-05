import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import '../utils/bookmark_import.dart';
import '../models/link.dart';

/// Service for managing persistent browser sync state
class BrowserSyncService {
  static final BrowserSyncService _instance = BrowserSyncService._internal();
  factory BrowserSyncService() => _instance;
  BrowserSyncService._internal();

  // Persistent state
  List<ImportedBookmark> _browserBookmarks = [];
  String? _loadedBookmarkFile;
  String? _loadedFilePath;
  bool _hasUnsavedChanges = false;

  // Getters
  List<ImportedBookmark> get browserBookmarks =>
      List.unmodifiable(_browserBookmarks);
  String? get loadedBookmarkFile => _loadedBookmarkFile;
  String? get loadedFilePath => _loadedFilePath;
  bool get hasLoadedBookmarks => _browserBookmarks.isNotEmpty;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  /// Load bookmarks from a file and persist the state
  Future<BrowserSyncLoadResult> loadBookmarkFile() async {
    try {
      final typeGroup = XTypeGroup(
        label: 'Bookmarks',
        extensions: ['html', 'json'],
      );
      final xfile = await openFile(acceptedTypeGroups: [typeGroup]);
      if (xfile == null) {
        return BrowserSyncLoadResult.cancelled();
      }

      final path = xfile.path;
      final text = await xfile.readAsString();

      ImportResult importResult;
      if (path.endsWith('.html') ||
          text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
        importResult = await importFromNetscapeHtml(
          text,
          createCollections: false,
        );
      } else if (path.endsWith('.json')) {
        importResult = await importFromChromeJson(
          jsonDecode(text),
          createCollections: false,
        );
      } else {
        throw Exception('Unsupported file format');
      }

      // Store the loaded bookmarks persistently
      _browserBookmarks = List.from(importResult.bookmarks);
      _loadedBookmarkFile = path.split('/').last;
      _loadedFilePath = path;

      return BrowserSyncLoadResult.success(
        bookmarks: _browserBookmarks,
        fileName: _loadedBookmarkFile!,
        filePath: path,
      );
    } catch (e) {
      return BrowserSyncLoadResult.error(e.toString());
    }
  }

  /// Reload the current bookmark file (useful for refreshing)
  Future<BrowserSyncLoadResult> reloadCurrentFile() async {
    if (_loadedFilePath == null) {
      return BrowserSyncLoadResult.error('No file currently loaded');
    }

    try {
      final file = XFile(_loadedFilePath!);
      final text = await file.readAsString();

      ImportResult importResult;
      if (_loadedFilePath!.endsWith('.html') ||
          text.startsWith('<!DOCTYPE NETSCAPE-Bookmark-file-1>')) {
        importResult = await importFromNetscapeHtml(
          text,
          createCollections: false,
        );
      } else if (_loadedFilePath!.endsWith('.json')) {
        importResult = await importFromChromeJson(
          jsonDecode(text),
          createCollections: false,
        );
      } else {
        throw Exception('Unsupported file format');
      }

      // Update the loaded bookmarks
      _browserBookmarks = List.from(importResult.bookmarks);

      return BrowserSyncLoadResult.success(
        bookmarks: _browserBookmarks,
        fileName: _loadedBookmarkFile!,
        filePath: _loadedFilePath!,
      );
    } catch (e) {
      return BrowserSyncLoadResult.error('Failed to reload file: $e');
    }
  }

  /// Clear the loaded bookmark data
  void clearLoadedBookmarks() {
    _browserBookmarks.clear();
    _loadedBookmarkFile = null;
    _loadedFilePath = null;
    _hasUnsavedChanges = false;
  }

  /// Add Kioju links to the in-memory bookmark list (staging)
  AddLinksResult addKiojuLinksToBookmarks(List<LinkItem> kiojuLinks) {
    final existingUrls = _browserBookmarks.map((b) => b.url).toSet();
    int added = 0;
    int duplicates = 0;
    final duplicateUrls = <String>[];

    for (final link in kiojuLinks) {
      if (!existingUrls.contains(link.url)) {
        _browserBookmarks.add(
          ImportedBookmark(
            link.url,
            title: link.title ?? link.url,
            collection: link.collection,
          ),
        );
        existingUrls.add(link.url);
        added++;
      } else {
        duplicates++;
        duplicateUrls.add(link.url);
      }
    }

    if (added > 0) {
      _hasUnsavedChanges = true;
    }

    return AddLinksResult(
      added: added,
      duplicates: duplicates,
      duplicateUrls: duplicateUrls,
    );
  }

  /// Save the current in-memory bookmark list to the loaded file
  Future<bool> saveToLoadedFile() async {
    if (_loadedFilePath == null) return false;

    try {
      final html = _generateBookmarkHtml();
      await File(_loadedFilePath!).writeAsString(html);
      _hasUnsavedChanges = false;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Save the current in-memory bookmark list with a save dialog
  Future<SaveResult> saveWithDialog() async {
    try {
      // Suggest the currently loaded file name if available
      final suggestedName = _loadedBookmarkFile ?? 'bookmarks.html';

      final file = await getSaveLocation(suggestedName: suggestedName);
      if (file == null) {
        return SaveResult.cancelled();
      }

      final html = _generateBookmarkHtml();
      await File(file.path).writeAsString(html);
      _hasUnsavedChanges = false;

      return SaveResult.success(
        path: file.path,
        bookmarkCount: _browserBookmarks.length,
      );
    } catch (e) {
      return SaveResult.error(e.toString());
    }
  }

  /// Generate HTML from current bookmark list
  String _generateBookmarkHtml() {
    final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    final header =
        '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n'
        '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n'
        '<TITLE>Bookmarks</TITLE>\n'
        '<H1>Bookmarks</H1>\n'
        '<DL><p>\n';

    final body = _browserBookmarks
        .map(
          (b) =>
              '    <DT><A HREF="${_escapeHtml(b.url)}" ADD_DATE="$ts" LAST_MODIFIED="$ts">${_escapeHtml(b.title ?? b.url)}</A>',
        )
        .join('\n');

    return '$header$body\n</DL><p>\n';
  }

  String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  /// Get summary information about the loaded state
  BrowserSyncStateSummary getStateSummary() {
    return BrowserSyncStateSummary(
      hasLoadedFile: _loadedBookmarkFile != null,
      fileName: _loadedBookmarkFile,
      filePath: _loadedFilePath,
      bookmarkCount: _browserBookmarks.length,
      lastLoaded: _loadedBookmarkFile != null ? DateTime.now() : null,
    );
  }

  /// Check if a specific bookmark URL exists in the loaded bookmarks
  bool containsBookmark(String url) {
    return _browserBookmarks.any((bookmark) => bookmark.url == url);
  }

  /// Get bookmarks by collection
  Map<String?, List<ImportedBookmark>> getBookmarksByCollection() {
    final Map<String?, List<ImportedBookmark>> grouped = {};

    for (final bookmark in _browserBookmarks) {
      final collection = bookmark.collection;
      if (!grouped.containsKey(collection)) {
        grouped[collection] = [];
      }
      grouped[collection]!.add(bookmark);
    }

    return grouped;
  }

  /// Get all unique collections from loaded bookmarks
  List<String> getCollections() {
    final collections =
        _browserBookmarks
            .map((b) => b.collection)
            .where((c) => c != null)
            .cast<String>()
            .toSet()
            .toList();
    collections.sort();
    return collections;
  }
}

/// Result of loading a bookmark file
class BrowserSyncLoadResult {
  final bool success;
  final List<ImportedBookmark>? bookmarks;
  final String? fileName;
  final String? filePath;
  final String? error;

  const BrowserSyncLoadResult._({
    required this.success,
    this.bookmarks,
    this.fileName,
    this.filePath,
    this.error,
  });

  factory BrowserSyncLoadResult.success({
    required List<ImportedBookmark> bookmarks,
    required String fileName,
    required String filePath,
  }) {
    return BrowserSyncLoadResult._(
      success: true,
      bookmarks: bookmarks,
      fileName: fileName,
      filePath: filePath,
    );
  }

  factory BrowserSyncLoadResult.cancelled() {
    return const BrowserSyncLoadResult._(success: false);
  }

  factory BrowserSyncLoadResult.error(String error) {
    return BrowserSyncLoadResult._(success: false, error: error);
  }

  String get message {
    if (!success) {
      return error ?? 'Operation cancelled';
    }
    return 'Loaded ${bookmarks!.length} bookmarks from $fileName';
  }
}

/// Summary of the current browser sync state
class BrowserSyncStateSummary {
  final bool hasLoadedFile;
  final String? fileName;
  final String? filePath;
  final int bookmarkCount;
  final DateTime? lastLoaded;

  const BrowserSyncStateSummary({
    required this.hasLoadedFile,
    this.fileName,
    this.filePath,
    required this.bookmarkCount,
    this.lastLoaded,
  });

  String get displayText {
    if (!hasLoadedFile) {
      return 'No bookmark file loaded';
    }
    return '$fileName ($bookmarkCount bookmarks)';
  }

  String get statusText {
    if (!hasLoadedFile) {
      return 'Click "Load Bookmark File" to get started';
    }
    return 'File: $fileName • $bookmarkCount bookmarks';
  }
}

/// Result of a save operation with dialog
class SaveResult {
  final bool success;
  final String? path;
  final int? bookmarkCount;
  final String? error;

  const SaveResult._({
    required this.success,
    this.path,
    this.bookmarkCount,
    this.error,
  });

  factory SaveResult.success({
    required String path,
    required int bookmarkCount,
  }) {
    return SaveResult._(
      success: true,
      path: path,
      bookmarkCount: bookmarkCount,
    );
  }

  factory SaveResult.cancelled() {
    return const SaveResult._(success: false);
  }

  factory SaveResult.error(String error) {
    return SaveResult._(success: false, error: error);
  }

  String get message {
    if (!success) {
      return error ?? 'Save cancelled';
    }
    return 'Saved $bookmarkCount bookmarks to ${path!.split('/').last.split('\\').last}';
  }
}

/// Result of adding links to bookmark list
class AddLinksResult {
  final int added;
  final int duplicates;
  final List<String> duplicateUrls;

  const AddLinksResult({
    required this.added,
    required this.duplicates,
    required this.duplicateUrls,
  });

  String get message {
    if (added == 0 && duplicates > 0) {
      return duplicates == 1
          ? 'Link already exists in bookmark list'
          : '$duplicates links already exist in bookmark list';
    } else if (added > 0 && duplicates == 0) {
      return added == 1
          ? 'Added 1 link to bookmark list'
          : 'Added $added links to bookmark list';
    } else if (added > 0 && duplicates > 0) {
      return 'Added $added links, $duplicates already existed';
    } else {
      return 'No links to add';
    }
  }
}
