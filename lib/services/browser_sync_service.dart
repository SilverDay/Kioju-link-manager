import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import '../utils/bookmark_import.dart';

/// Service for managing persistent browser sync state
class BrowserSyncService {
  static final BrowserSyncService _instance = BrowserSyncService._internal();
  factory BrowserSyncService() => _instance;
  BrowserSyncService._internal();

  // Persistent state
  List<ImportedBookmark> _browserBookmarks = [];
  String? _loadedBookmarkFile;
  String? _loadedFilePath;

  // Getters
  List<ImportedBookmark> get browserBookmarks =>
      List.unmodifiable(_browserBookmarks);
  String? get loadedBookmarkFile => _loadedBookmarkFile;
  String? get loadedFilePath => _loadedFilePath;
  bool get hasLoadedBookmarks => _browserBookmarks.isNotEmpty;

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
      _browserBookmarks = importResult.bookmarks;
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
      _browserBookmarks = importResult.bookmarks;

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
  }

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
