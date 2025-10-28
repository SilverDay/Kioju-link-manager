/// Utility functions for URL normalization and comparison
class UrlUtils {
  /// Normalizes a URL for consistent comparison and duplicate detection
  /// Removes common variations that should be considered the same URL
  static String normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url.trim().toLowerCase());

      // Ensure scheme is present (default to https)
      var scheme = uri.scheme;
      if (scheme.isEmpty) {
        scheme = 'https';
      }

      // Normalize host (remove www. prefix)
      var host = uri.host;
      if (host.startsWith('www.')) {
        host = host.substring(4);
      }

      // Normalize path (remove trailing slash except for root)
      var path = uri.path;
      if (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (path.isEmpty) {
        path = '/';
      }

      // Rebuild normalized URL
      final normalizedUri = Uri(
        scheme: scheme,
        host: host,
        port: uri.hasPort ? uri.port : null,
        path: path,
        query: uri.query.isNotEmpty ? uri.query : null,
        fragment: uri.fragment.isNotEmpty ? uri.fragment : null,
      );

      return normalizedUri.toString();
    } catch (e) {
      // If parsing fails, return original URL
      return url.trim().toLowerCase();
    }
  }

  /// Checks if two URLs are equivalent after normalization
  static bool areUrlsEquivalent(String url1, String url2) {
    return normalizeUrl(url1) == normalizeUrl(url2);
  }

  /// Gets all possible variations of a URL for duplicate checking
  /// Returns a list of normalized URLs that should be considered duplicates
  static List<String> getUrlVariations(String url) {
    final variations = <String>{};

    try {
      final uri = Uri.parse(url.trim());
      final baseUrl = url.trim().toLowerCase();

      // Add original (normalized)
      variations.add(normalizeUrl(baseUrl));

      // Add with/without www
      if (uri.host.startsWith('www.')) {
        final withoutWww = baseUrl.replaceFirst('www.', '');
        variations.add(normalizeUrl(withoutWww));
      } else {
        final withWww = baseUrl.replaceFirst('://', '://www.');
        variations.add(normalizeUrl(withWww));
      }

      // Add with/without trailing slash
      if (baseUrl.endsWith('/')) {
        variations.add(normalizeUrl(baseUrl.substring(0, baseUrl.length - 1)));
      } else {
        variations.add(normalizeUrl('$baseUrl/'));
      }

      // Add http/https variations
      if (baseUrl.startsWith('https://')) {
        variations.add(
          normalizeUrl(baseUrl.replaceFirst('https://', 'http://')),
        );
      } else if (baseUrl.startsWith('http://')) {
        variations.add(
          normalizeUrl(baseUrl.replaceFirst('http://', 'https://')),
        );
      }
    } catch (e) {
      // If parsing fails, just add the normalized original
      variations.add(normalizeUrl(url));
    }

    return variations.toList();
  }
}
