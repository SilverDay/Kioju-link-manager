import 'package:html/parser.dart' as html_parser;
import 'security_utils.dart';
import '../services/collection_service.dart';

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
  final Map<String, String> conflictResolutions; // original -> resolved name
  
  ImportResult({
    required this.bookmarks,
    this.collectionsCreated = const [],
    this.collectionConflicts = const [],
    this.conflictResolutions = const {},
  });
}

Future<ImportResult> importFromNetscapeHtml(String html, {
  bool createCollections = true,
  Map<String, String>? collectionNameMappings,
}) async {
  // Validate HTML content first
  final validation = SecurityUtils.validateHtmlContent(html);
  if (!validation.isValid) {
    throw ArgumentError('Invalid HTML content: ${validation.message}');
  }

  try {
    final doc = html_parser.parse(html);
    final bookmarks = <ImportedBookmark>[];
    final collectionsFound = <String>{};
    final collectionsCreated = <String>[];
    final collectionConflicts = <String>[];
    final conflictResolutions = <String, String>{};

    // Parse folder structure from HTML
    final folders = doc.querySelectorAll('dt');
    String? currentCollection;

    for (final dt in folders) {
      // Check if this is a folder (H3 element)
      final h3 = dt.querySelector('h3');
      if (h3 != null) {
        final folderName = h3.text.trim();
        if (folderName.isNotEmpty) {
          final nameValidation = SecurityUtils.validateTitle(folderName);
          if (nameValidation.isValid && nameValidation.sanitizedValue != null) {
            currentCollection = nameValidation.sanitizedValue!;
            collectionsFound.add(currentCollection!);
          }
        }
        continue;
      }

      // Check if this is a link (A element)
      final a = dt.querySelector('a[href]');
      if (a != null) {
        final href = a.attributes['href'];
        if (href == null || href.isEmpty) continue;

        // Validate each URL
        final urlValidation = SecurityUtils.validateUrl(href);
        if (!urlValidation.isValid) {
          // Skip invalid URLs instead of failing the entire import
          continue;
        }

        final title = a.text.trim();
        final titleValidation = SecurityUtils.validateTitle(title);

        // Apply collection name mapping if provided
        String? finalCollection = currentCollection;
        if (finalCollection != null && collectionNameMappings != null) {
          finalCollection = collectionNameMappings[finalCollection] ?? finalCollection;
        }

        bookmarks.add(
          ImportedBookmark(
            urlValidation.sanitizedValue,
            title: titleValidation.isValid && titleValidation.sanitizedValue != null
                ? titleValidation.sanitizedValue
                : null,
            collection: finalCollection,
          ),
        );
      }
    }

    // Create collections if requested
    if (createCollections) {
      final collectionService = CollectionService.instance;
      
      for (final collectionName in collectionsFound) {
        // Get the final collection name (mapped if provided)
        final finalCollectionName = collectionNameMappings?[collectionName] ?? collectionName;
        
        try {
          // Check if collection already exists (use final name for checking)
          final existing = await collectionService.getCollectionByName(finalCollectionName);
          
          if (existing == null) {
            // Create new collection with final name
            await collectionService.createCollection(
              name: finalCollectionName,
              description: 'Created from bookmark import',
              visibility: 'private',
            );
            collectionsCreated.add(finalCollectionName);
          } else {
            // Collection already exists - this is a conflict (only if no mapping provided)
            if (collectionNameMappings == null || !collectionNameMappings.containsKey(collectionName)) {
              collectionConflicts.add(collectionName);
            }
          }
        } catch (e) {
          // If creation fails, treat as conflict (only if no mapping provided)
          if (collectionNameMappings == null || !collectionNameMappings.containsKey(collectionName)) {
            collectionConflicts.add(collectionName);
          }
        }
      }
    }

    return ImportResult(
      bookmarks: bookmarks,
      collectionsCreated: collectionsCreated,
      collectionConflicts: collectionConflicts,
      conflictResolutions: conflictResolutions,
    );
  } catch (e) {
    throw Exception('Failed to parse HTML bookmarks: $e');
  }
}

Future<ImportResult> importFromChromeJson(Map<String, dynamic> json, {
  bool createCollections = true,
  Map<String, String>? collectionNameMappings,
}) async {
  final bookmarks = <ImportedBookmark>[];
  final collectionsFound = <String>{};
  final collectionsCreated = <String>[];
  final collectionConflicts = <String>[];
  final conflictResolutions = <String, String>{};

  void walk(Map<String, dynamic> node, List<String> path) {
    try {
      final type = node['type'];
      if (type == 'url') {
        final url = node['url'];
        if (url is String) {
          // Validate URL
          final urlValidation = SecurityUtils.validateUrl(url);
          if (!urlValidation.isValid) {
            // Skip invalid URLs
            return;
          }

          final name = node['name'];
          final title = name is String ? name : null;
          final titleValidation = SecurityUtils.validateTitle(title);

          // Create collection name from path (skip root level like "Bookmarks bar")
          String? collection;
          if (path.length > 1) {
            // Use only the immediate parent folder, not the full path
            collection = path.last;
            final collectionValidation = SecurityUtils.validateTitle(collection);
            if (collectionValidation.isValid && collectionValidation.sanitizedValue != null) {
              collection = collectionValidation.sanitizedValue!;
              
              // Apply collection name mapping if provided
              if (collectionNameMappings != null) {
                collection = collectionNameMappings[collection] ?? collection;
              }
              
              collectionsFound.add(collection!);
            } else {
              collection = null;
            }
          }

          bookmarks.add(
            ImportedBookmark(
              urlValidation.sanitizedValue,
              title: titleValidation.isValid && titleValidation.sanitizedValue != null
                  ? titleValidation.sanitizedValue
                  : null,
              collection: collection,
            ),
          );
        }
      }

      final children = node['children'];
      if (children is List) {
        // Validate folder name
        final nodeName = node['name'];
        final folderName = nodeName is String ? nodeName : null;
        final nameValidation = SecurityUtils.validateTitle(folderName);

        final nextPath =
            (type == 'folder' &&
                    nameValidation.isValid &&
                    nameValidation.sanitizedValue != null)
                ? [...path, nameValidation.sanitizedValue!]
                : path;

        for (final c in children) {
          if (c is Map<String, dynamic>) {
            walk(c, List<String>.from(nextPath));
          }
        }
      }
    } catch (e) {
      // Skip nodes that cause errors instead of failing the entire import
      return;
    }
  }

  try {
    final roots = json['roots'];
    if (roots is Map<String, dynamic>) {
      for (final key in roots.keys) {
        final root = roots[key];
        if (root is Map<String, dynamic>) {
          walk(root, [key]);
        }
      }
    }
  } catch (e) {
    throw Exception('Failed to parse Chrome JSON bookmarks: $e');
  }

  // Create collections if requested
  if (createCollections) {
    final collectionService = CollectionService.instance;
    
    for (final collectionName in collectionsFound) {
      try {
        // Check if collection already exists
        final existing = await collectionService.getCollectionByName(collectionName);
        
        if (existing == null) {
          // Create new collection
          await collectionService.createCollection(
            name: collectionName,
            description: 'Created from bookmark import',
            visibility: 'private',
          );
          collectionsCreated.add(collectionName);
        } else {
          // Collection already exists - this is a conflict
          collectionConflicts.add(collectionName);
        }
      } catch (e) {
        // If creation fails, treat as conflict
        collectionConflicts.add(collectionName);
      }
    }
  }

  return ImportResult(
    bookmarks: bookmarks,
    collectionsCreated: collectionsCreated,
    collectionConflicts: collectionConflicts,
    conflictResolutions: conflictResolutions,
  );
}
