import 'package:html/parser.dart' as html_parser;
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

List<ImportedBookmark> importFromNetscapeHtml(String html) {
  // Validate HTML content first
  final validation = SecurityUtils.validateHtmlContent(html);
  if (!validation.isValid) {
    throw ArgumentError('Invalid HTML content: ${validation.message}');
  }

  try {
    final doc = html_parser.parse(html);
    final anchors = doc.querySelectorAll('a[href]');
    final bookmarks = <ImportedBookmark>[];

    for (final a in anchors) {
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

      bookmarks.add(
        ImportedBookmark(
          urlValidation.sanitizedValue,
          title:
              titleValidation.isValid && titleValidation.sanitizedValue != null
                  ? titleValidation.sanitizedValue
                  : null,
        ),
      );
    }

    return bookmarks;
  } catch (e) {
    throw Exception('Failed to parse HTML bookmarks: $e');
  }
}

List<ImportedBookmark> importFromChromeJson(Map<String, dynamic> json) {
  final bookmarks = <ImportedBookmark>[];

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

          // Validate collection path
          final collection = path.join('/');
          final collectionValidation = SecurityUtils.validateTitle(collection);

          bookmarks.add(
            ImportedBookmark(
              urlValidation.sanitizedValue,
              title:
                  titleValidation.isValid &&
                          titleValidation.sanitizedValue != null
                      ? titleValidation.sanitizedValue
                      : null,
              collection:
                  collectionValidation.isValid &&
                          collectionValidation.sanitizedValue != null
                      ? collectionValidation.sanitizedValue
                      : null,
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

  return bookmarks;
}
