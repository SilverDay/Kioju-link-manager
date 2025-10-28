import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

class WebMetadata {
  final String? title;
  final String? description;
  final String? siteName;
  final String? imageUrl;

  const WebMetadata({
    this.title,
    this.description,
    this.siteName,
    this.imageUrl,
  });

  @override
  String toString() {
    return 'WebMetadata(title: $title, description: $description, siteName: $siteName, imageUrl: $imageUrl)';
  }
}

class WebMetadataService {
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxContentLength = 1024 * 1024; // 1MB limit

  /// Fetches web metadata (title, description) from a URL
  /// Returns null if the URL is invalid, unreachable, or parsing fails
  static Future<WebMetadata?> fetchMetadata(String url) async {
    try {
      // Validate and normalize URL
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return null;
      }

      // Ensure HTTPS/HTTP scheme
      if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
        return null;
      }

      // Make HTTP request with timeout
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Kioju Link Manager (Mozilla/5.0 compatible)',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
              'Accept-Encoding': 'gzip, deflate',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(_timeout);

      // Check response status
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return null;
      }

      // Check content type
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().contains('text/html')) {
        return null;
      }

      // Check content length
      final contentLength = response.contentLength ?? response.body.length;
      if (contentLength > _maxContentLength) {
        return null;
      }

      // Parse HTML
      final document = html_parser.parse(response.body);
      return _extractMetadata(document, uri);
    } catch (e) {
      // Silently fail on any error (network, parsing, etc.)
      return null;
    }
  }

  static WebMetadata _extractMetadata(Document document, Uri uri) {
    String? title;
    String? description;
    String? siteName;
    String? imageUrl;

    // Extract title (priority order)
    title =
        _getMetaProperty(document, 'og:title') ??
        _getMetaProperty(document, 'twitter:title') ??
        _getMetaName(document, 'title') ??
        document.querySelector('title')?.text.trim();

    // Extract description (priority order)
    description =
        _getMetaProperty(document, 'og:description') ??
        _getMetaProperty(document, 'twitter:description') ??
        _getMetaName(document, 'description') ??
        _getMetaName(document, 'Description');

    // Extract site name
    siteName =
        _getMetaProperty(document, 'og:site_name') ??
        _getMetaProperty(document, 'twitter:site')?.replaceAll('@', '') ??
        uri.host.replaceAll('www.', '');

    // Extract image URL
    imageUrl =
        _getMetaProperty(document, 'og:image') ??
        _getMetaProperty(document, 'twitter:image') ??
        _getMetaName(document, 'image');

    // Clean up extracted data
    title = _cleanText(title);
    description = _cleanText(description);
    siteName = _cleanText(siteName);

    // Use site name as fallback title if no title found
    if ((title == null || title.isEmpty) && siteName != null) {
      title = siteName;
    }

    // Generate fallback title from URL if still empty
    if (title == null || title.isEmpty) {
      title = _generateFallbackTitle(uri);
    }

    return WebMetadata(
      title: title,
      description: description,
      siteName: siteName,
      imageUrl: imageUrl,
    );
  }

  static String? _getMetaProperty(Document document, String property) {
    return document
        .querySelector('meta[property="$property"]')
        ?.attributes['content'];
  }

  static String? _getMetaName(Document document, String name) {
    return document.querySelector('meta[name="$name"]')?.attributes['content'];
  }

  static String? _cleanText(String? text) {
    if (text == null) return null;

    // Remove excessive whitespace and newlines
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Limit length to reasonable size
    if (text.length > 200) {
      text = '${text.substring(0, 200).trim()}...';
    }

    return text.isEmpty ? null : text;
  }

  static String _generateFallbackTitle(Uri uri) {
    final host = uri.host.replaceAll('www.', '');
    final path = uri.path;

    if (path.length > 1) {
      // Try to extract meaningful part from path
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        // Convert URL-style names to readable format
        final readable =
            lastSegment
                .replaceAll('-', ' ')
                .replaceAll('_', ' ')
                .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
                .trim();
        if (readable.isNotEmpty && readable.length > 2) {
          return '${readable[0].toUpperCase()}${readable.substring(1)} - $host';
        }
      }
    }

    return host;
  }
}
