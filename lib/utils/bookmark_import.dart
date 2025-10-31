import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:sqflite/sqflite.dart';

import '../db.dart';
import 'security_utils.dart';

class ImportedBookmark {
  final String url;
  final String? title;
  final String? collection;
  final List<String> tags;

  ImportedBookmark(
    this.url, {
    this.title,
    this.collection,
    this.tags = const [],
  });
}

class ImportResult {
  final List<ImportedBookmark> bookmarks;
  final List<String> collectionsCreated;
  final List<String> collectionConflicts;
  final Map<String, String> conflictResolutions;

  ImportResult({
    required List<ImportedBookmark> bookmarks,
    List<String>? collectionsCreated,
    List<String>? collectionConflicts,
    Map<String, String>? conflictResolutions,
  }) : bookmarks = List.unmodifiable(bookmarks),
       collectionsCreated = List.unmodifiable(
         List<String>.from(collectionsCreated ?? const [])..sort(),
       ),
       collectionConflicts = List.unmodifiable(
         List<String>.from(collectionConflicts ?? const [])..sort(),
       ),
       conflictResolutions = Map.unmodifiable(conflictResolutions ?? const {});

  factory ImportResult.empty() => ImportResult(bookmarks: const []);
}

class _CollectionImportHelper {
  _CollectionImportHelper({
    required this.db,
    required this.createCollections,
    required Map<String, String>? collectionNameMappings,
    required Set<String> initialCollectionNames,
  }) : _existingCollectionNames = initialCollectionNames,
       _collectionNameMappings = _sanitizeMappings(collectionNameMappings);

  final Database db;
  final bool createCollections;
  final Set<String> _existingCollectionNames;
  final Map<String, String> _collectionNameMappings;
  final Set<String> collectionsCreated = <String>{};
  final Set<String> collectionConflicts = <String>{};
  final Map<String, String> conflictResolutions = <String, String>{};
  final Map<String, Future<String?>> _resolutionCache = {};

  Future<String?> resolveCollection(String? candidatePath) {
    if (candidatePath == null || candidatePath.trim().isEmpty) {
      return Future.value(null);
    }

    final validation = SecurityUtils.validateTitle(candidatePath);
    if (!validation.isValid) {
      collectionConflicts.add(candidatePath.trim());
      return Future.value(null);
    }

    final sanitized = validation.sanitizedValue ?? candidatePath.trim();
    if (sanitized.isEmpty) {
      return Future.value(null);
    }

    final cached = _resolutionCache[sanitized];
    if (cached != null) {
      return cached;
    }

    final future = _resolveInternal(sanitized);
    _resolutionCache[sanitized] = future;
    return future;
  }

  Future<String?> _resolveInternal(String key) async {
    if (_collectionNameMappings.containsKey(key)) {
      final mapped = _collectionNameMappings[key]!;
      if (mapped.isEmpty) {
        conflictResolutions[key] = '';
        collectionConflicts.add(key);
        return null;
      }

      conflictResolutions[key] = mapped;
      await _ensureCollectionExists(mapped, markCreated: true);
      return mapped;
    }

    if (_existingCollectionNames.contains(key)) {
      collectionConflicts.add(key);
      return key;
    }

    if (!createCollections) {
      collectionConflicts.add(key);
      return null;
    }

    await _ensureCollectionExists(key, markCreated: true);
    return key;
  }

  Future<void> _ensureCollectionExists(
    String name, {
    bool markCreated = false,
  }) async {
    if (_existingCollectionNames.contains(name)) {
      if (markCreated) {
        collectionsCreated.add(name);
      }
      return;
    }

    final now = DateTime.now().toIso8601String();

    try {
      final insertedId = await db.insert('collections', {
        'name': name,
        'description': 'Created from bookmark import',
        'visibility': 'public',
        'link_count': 0,
        'is_dirty': 1,
        'created_at': now,
        'updated_at': now,
        'last_synced_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      _existingCollectionNames.add(name);

      if (insertedId != 0) {
        collectionsCreated.add(name);
      }
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) {
        collectionConflicts.add(name);
      }
      _existingCollectionNames.add(name);
    } catch (_) {
      collectionConflicts.add(name);
    }
  }

  static Map<String, String> _sanitizeMappings(Map<String, String>? raw) {
    if (raw == null || raw.isEmpty) return const {};

    final sanitized = <String, String>{};

    raw.forEach((key, value) {
      final keyValidation = SecurityUtils.validateTitle(key);
      if (!keyValidation.isValid) return;
      final sanitizedKey = keyValidation.sanitizedValue ?? key.trim();
      if (sanitizedKey.isEmpty) return;

      if (value.trim().isEmpty) {
        sanitized[sanitizedKey] = '';
        return;
      }

      final valueValidation = SecurityUtils.validateTitle(value);
      if (!valueValidation.isValid) return;
      final sanitizedValue = valueValidation.sanitizedValue ?? value.trim();
      if (sanitizedValue.isEmpty) return;

      sanitized[sanitizedKey] = sanitizedValue;
    });

    return sanitized;
  }
}

Future<ImportResult> importFromNetscapeHtml(
  String html, {
  bool createCollections = false,
  Map<String, String>? collectionNameMappings,
}) async {
  final validation = SecurityUtils.validateHtmlContent(html);
  if (!validation.isValid) {
    throw ArgumentError('Invalid HTML content: ${validation.message}');
  }

  final db = await AppDb.instance();
  final existingRows = await db.query('collections', columns: ['name']);
  final existingNames =
      existingRows
          .map((row) => (row['name'] as String?)?.trim())
          .whereType<String>()
          .toSet();

  final helper = _CollectionImportHelper(
    db: db,
    createCollections: createCollections,
    collectionNameMappings: collectionNameMappings,
    initialCollectionNames: existingNames,
  );

  final bookmarks = <ImportedBookmark>[];
  final doc = html_parser.parse(html);
  final body = doc.body;

  // Track processed elements to avoid infinite loops
  final processed = <dom.Element>{};

  late Future<void> Function(dom.Element, List<String>) walkElement;
  late Future<void> Function(dom.Element, List<String>) processDt;

  processDt = (dom.Element dt, List<String> segments) async {
    if (processed.contains(dt)) {
      return;
    }
    processed.add(dt);

    // Check if this DT contains a folder (H3)
    dom.Element? folderHeader;
    dom.Element? nestedDl;

    for (final child in dt.children) {
      if (child.localName == 'h3') {
        folderHeader = child;
      } else if (child.localName == 'dl') {
        nestedDl = child;
      }
    }

    // If no nested DL found in children, check next sibling
    if (nestedDl == null) {
      dom.Element? sibling = dt.nextElementSibling;
      if (sibling?.localName == 'dl') {
        nestedDl = sibling;
      }
    }

    // This is a folder
    if (folderHeader != null) {
      final folderValidation = SecurityUtils.validateTitle(folderHeader.text);
      if (folderValidation.isValid) {
        final sanitizedSegment =
            folderValidation.sanitizedValue ?? folderHeader.text.trim();
        if (sanitizedSegment.isNotEmpty) {
          final candidateSegments = [...segments, sanitizedSegment];
          final candidatePath = candidateSegments.join('/');
          final resolved = await helper.resolveCollection(candidatePath);
          final nextSegments =
              resolved == null ? segments : resolved.split('/');

          if (nestedDl != null) {
            await walkElement(nestedDl, nextSegments);
          }
          return;
        }
      }

      // Invalid folder name, but still process nested content
      if (nestedDl != null) {
        await walkElement(nestedDl, segments);
      }
      return;
    }

    // This is a bookmark (has an anchor tag)
    final anchor = _firstAnchor(dt);
    if (anchor != null) {
      processed.add(anchor); // Mark anchor as processed
      final bookmark = _bookmarkFromAnchor(
        anchor,
        segments.isEmpty ? null : segments.join('/'),
      );
      if (bookmark != null) {
        bookmarks.add(bookmark);
      }
    }
  };

  walkElement = (dom.Element element, List<String> segments) async {
    // Prevent infinite loops by tracking processed elements
    if (processed.contains(element)) {
      return;
    }
    processed.add(element);

    // Handle DL (definition list) - contains folders/bookmarks
    if (element.localName == 'dl') {
      for (final child in element.children) {
        if (child.localName == 'dt') {
          await processDt(child, segments);
        }
      }
      return;
    }

    // Recursively process children for other elements
    for (final child in element.children) {
      await walkElement(child, segments);
    }
  };

  if (body != null) {
    await walkElement(body, const []);

    // Fallback: if no bookmarks found through structure, try finding all anchors
    if (bookmarks.isEmpty) {
      for (final anchor in body.querySelectorAll('a[href]')) {
        if (!processed.contains(anchor)) {
          final bookmark = _bookmarkFromAnchor(anchor, null);
          if (bookmark != null) {
            bookmarks.add(bookmark);
          }
        }
      }
    }
  }

  // Deduplicate bookmarks by URL (keep first occurrence)
  final seenUrls = <String>{};
  final dedupedBookmarks = <ImportedBookmark>[];
  for (final bookmark in bookmarks) {
    if (!seenUrls.contains(bookmark.url)) {
      seenUrls.add(bookmark.url);
      dedupedBookmarks.add(bookmark);
    }
  }

  return ImportResult(
    bookmarks: dedupedBookmarks,
    collectionsCreated: helper.collectionsCreated.toList(),
    collectionConflicts: helper.collectionConflicts.toList(),
    conflictResolutions: helper.conflictResolutions,
  );
}

Future<ImportResult> importFromChromeJson(
  Map<String, dynamic> json, {
  bool createCollections = false,
  Map<String, String>? collectionNameMappings,
}) async {
  final db = await AppDb.instance();
  final existingRows = await db.query('collections', columns: ['name']);
  final existingNames =
      existingRows
          .map((row) => (row['name'] as String?)?.trim())
          .whereType<String>()
          .toSet();

  final helper = _CollectionImportHelper(
    db: db,
    createCollections: createCollections,
    collectionNameMappings: collectionNameMappings,
    initialCollectionNames: existingNames,
  );

  final bookmarks = <ImportedBookmark>[];

  Future<void> visitNode(
    Map<String, dynamic> node,
    List<String> currentSegments,
  ) async {
    final type = node['type'];

    if (type == 'url') {
      final url = node['url'];
      if (url is! String) {
        return;
      }

      final urlValidation = SecurityUtils.validateUrl(url);
      if (!urlValidation.isValid) {
        return;
      }

      final name = node['name'];
      final title = name is String ? name : null;
      final titleValidation = SecurityUtils.validateTitle(title);
      final collectionPath =
          currentSegments.isEmpty ? null : currentSegments.join('/');

      bookmarks.add(
        ImportedBookmark(
          urlValidation.sanitizedValue,
          title:
              titleValidation.isValid ? titleValidation.sanitizedValue : null,
          collection: collectionPath,
        ),
      );
      return;
    }

    if (type == 'folder' || node.containsKey('children')) {
      final name = node['name'];
      String? resolvedPath;

      if (name is String && name.trim().isNotEmpty) {
        final titleValidation = SecurityUtils.validateTitle(name);
        final sanitizedSegment =
            titleValidation.isValid && titleValidation.sanitizedValue != null
                ? titleValidation.sanitizedValue!
                : name.trim();

        final candidateSegments = [...currentSegments, sanitizedSegment];
        final candidatePath = candidateSegments.join('/');
        resolvedPath = await helper.resolveCollection(candidatePath);
      }

      final nextSegments = resolvedPath?.split('/') ?? currentSegments;
      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          if (child is Map<String, dynamic>) {
            await visitNode(child, nextSegments);
          }
        }
      }
    }
  }

  final roots = json['roots'];
  if (roots is Map<String, dynamic>) {
    for (final entry in roots.values) {
      if (entry is Map<String, dynamic>) {
        await visitNode(entry, const []);
      }
    }
  }

  // Deduplicate bookmarks by URL (keep first occurrence)
  final seenUrls = <String>{};
  final dedupedBookmarks = <ImportedBookmark>[];
  for (final bookmark in bookmarks) {
    if (!seenUrls.contains(bookmark.url)) {
      seenUrls.add(bookmark.url);
      dedupedBookmarks.add(bookmark);
    }
  }

  return ImportResult(
    bookmarks: dedupedBookmarks,
    collectionsCreated: helper.collectionsCreated.toList(),
    collectionConflicts: helper.collectionConflicts.toList(),
    conflictResolutions: helper.conflictResolutions,
  );
}

dom.Element? _firstAnchor(dom.Element element) {
  for (final child in element.children) {
    if (child.localName == 'a') {
      return child;
    }
  }
  return null;
}

ImportedBookmark? _bookmarkFromAnchor(
  dom.Element anchor,
  String? collectionPath,
) {
  final href = anchor.attributes['href'];
  if (href == null || href.isEmpty) {
    return null;
  }

  final urlValidation = SecurityUtils.validateUrl(href);
  if (!urlValidation.isValid) {
    return null;
  }

  final rawTitle = anchor.text.trim();
  final titleValidation = SecurityUtils.validateTitle(
    rawTitle.isEmpty ? null : rawTitle,
  );

  return ImportedBookmark(
    urlValidation.sanitizedValue,
    title: titleValidation.isValid ? titleValidation.sanitizedValue : null,
    collection: collectionPath,
  );
}
