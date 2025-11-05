import '../models/link.dart';

String escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String exportToNetscapeHtml(List<LinkItem> links) {
  final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
  final header =
      '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n'
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n'
      '<TITLE>Bookmarks</TITLE>\n'
      '<H1>Bookmarks</H1>\n'
      '<DL><p>\n';
  final body = links
      .map(
        (l) =>
            '    <DT><A HREF="${escapeHtml(l.url)}" ADD_DATE="$ts" LAST_MODIFIED="$ts">${escapeHtml(l.title ?? l.url)}</A>',
      )
      .join('\n');
  return '$header$body\n</DL><p>\n';
}

/// Merges Kioju links with existing browser bookmarks
String mergeWithExistingBookmarks(
  List<LinkItem> kiojuLinks,
  String existingHtml,
) {
  final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();

  // Extract existing bookmarks from HTML (everything between <DL><p> and </DL><p>)
  final dlStart = existingHtml.indexOf('<DL><p>');
  final dlEnd = existingHtml.indexOf('</DL><p>');

  if (dlStart == -1 || dlEnd == -1) {
    // If we can't parse existing HTML, just export Kioju links
    return exportToNetscapeHtml(kiojuLinks);
  }

  final header = existingHtml.substring(0, dlStart + 7); // Include '<DL><p>\n'
  final existingBody = existingHtml.substring(dlStart + 7, dlEnd).trim();
  final footer = existingHtml.substring(dlEnd);

  // Get URLs from existing bookmarks to avoid duplicates
  final existingUrls = <String>{};
  final hrefRegex = RegExp(r'HREF="([^"]*)"');
  for (final match in hrefRegex.allMatches(existingBody)) {
    existingUrls.add(match.group(1)!);
  }

  // Add Kioju links that don't already exist
  final newLinks = kiojuLinks
      .where((link) => !existingUrls.contains(link.url))
      .map(
        (l) =>
            '    <DT><A HREF="${escapeHtml(l.url)}" ADD_DATE="$ts" LAST_MODIFIED="$ts">${escapeHtml(l.title ?? l.url)}</A>',
      )
      .join('\n');

  // Combine existing bookmarks with new Kioju links
  final combinedBody =
      existingBody.isEmpty ? newLinks : '$existingBody\n$newLinks';

  return '$header$combinedBody\n$footer';
}
