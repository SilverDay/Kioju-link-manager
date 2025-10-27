import 'package:html/parser.dart' as html_parser;

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
  final doc = html_parser.parse(html);
  final anchors = doc.querySelectorAll('a[href]');
  return anchors.map((a) {
    final href = a.attributes['href']!;
    final title = a.text.trim();
    return ImportedBookmark(href, title: title.isNotEmpty ? title : null);
  }).toList();
}

List<ImportedBookmark> importFromChromeJson(Map<String, dynamic> json) {
  List<ImportedBookmark> out = [];
  void walk(Map<String, dynamic> node, List<String> path) {
    final type = node['type'];
    if (type == 'url') {
      out.add(
        ImportedBookmark(
          node['url'],
          title: node['name'],
          collection: path.join('/'),
        ),
      );
    }
    final children = node['children'];
    if (children is List) {
      final nextPath =
          (type == 'folder' && node['name'] != null)
              ? [...path, node['name'] as String]
              : path;
      for (final c in children) {
        walk(Map<String, dynamic>.from(c), nextPath);
      }
    }
  }

  final roots = Map<String, dynamic>.from(json['roots'] ?? {});
  for (final key in roots.keys) {
    walk(Map<String, dynamic>.from(roots[key]), [key]);
  }
  return out;
}
