import '../models/link.dart';

String escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String exportToNetscapeHtml(List<LinkItem> links) {
  final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
  final header = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n'
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n'
      '<TITLE>Bookmarks</TITLE>\n'
      '<H1>Bookmarks</H1>\n'
      '<DL><p>\n';
  final body = links
      .map((l) =>
          '    <DT><A HREF="${escapeHtml(l.url)}" ADD_DATE="$ts" LAST_MODIFIED="$ts">${escapeHtml(l.title ?? l.url)}</A>')
      .join('\n');
  return header + body + '\n</DL><p>\n';
}
