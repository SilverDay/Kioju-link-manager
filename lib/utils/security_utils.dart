import 'dart:convert';

/// Security utilities for input validation and sanitization
class SecurityUtils {
  // Maximum lengths to prevent buffer overflow attacks
  static const int maxUrlLength = 2048;
  static const int maxTitleLength = 500;
  static const int maxNotesLength = 5000;
  static const int maxTagLength = 100;
  static const int maxTagsCount = 50;

  // Regex patterns for validation
  static final RegExp _urlPattern = RegExp(
    r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
    caseSensitive: false,
  );

  // List of potentially dangerous URL schemes and patterns
  static final List<String> _dangerousSchemes = [
    'javascript:',
    'data:',
    'vbscript:',
    'file:',
    'ftp:',
  ];

  static final List<String> _suspiciousPatterns = [
    '<script',
    'javascript:',
    'onload=',
    'onerror=',
    'onclick=',
    'eval(',
    'document.cookie',
  ];

  /// Validates and sanitizes a URL
  static ValidationResult validateUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return ValidationResult(false, 'URL cannot be empty');
    }

    final trimmedUrl = url.trim();

    // Check length
    if (trimmedUrl.length > maxUrlLength) {
      return ValidationResult(
        false,
        'URL is too long (max $maxUrlLength characters)',
      );
    }

    // Check for dangerous schemes
    final lowerUrl = trimmedUrl.toLowerCase();
    for (final scheme in _dangerousSchemes) {
      if (lowerUrl.startsWith(scheme)) {
        return ValidationResult(false, 'URL scheme not allowed: $scheme');
      }
    }

    // Check for suspicious patterns
    for (final pattern in _suspiciousPatterns) {
      if (lowerUrl.contains(pattern.toLowerCase())) {
        return ValidationResult(false, 'URL contains suspicious content');
      }
    }

    // Validate URL format
    if (!_urlPattern.hasMatch(trimmedUrl)) {
      return ValidationResult(false, 'Invalid URL format');
    }

    try {
      final uri = Uri.parse(trimmedUrl);

      // Additional URI validation
      if (!uri.hasScheme || !uri.hasAuthority) {
        return ValidationResult(false, 'URL must have scheme and domain');
      }

      // Check for localhost/internal IPs (optional security measure)
      if (_isLocalOrInternalUrl(uri)) {
        return ValidationResult(
          false,
          'Local or internal URLs are not allowed',
        );
      }

      return ValidationResult(true, 'Valid URL', sanitizedValue: trimmedUrl);
    } catch (e) {
      return ValidationResult(false, 'Invalid URL: ${e.toString()}');
    }
  }

  /// Validates and sanitizes a title
  static ValidationResult validateTitle(String? title) {
    if (title == null || title.trim().isEmpty) {
      return ValidationResult(true, 'Valid title', sanitizedValue: null);
    }

    final trimmedTitle = title.trim();

    // Check length
    if (trimmedTitle.length > maxTitleLength) {
      return ValidationResult(
        false,
        'Title is too long (max $maxTitleLength characters)',
      );
    }

    // Sanitize HTML and dangerous characters
    final sanitized = _sanitizeText(trimmedTitle);

    return ValidationResult(true, 'Valid title', sanitizedValue: sanitized);
  }

  /// Validates and sanitizes notes/description
  static ValidationResult validateNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) {
      return ValidationResult(true, 'Valid notes', sanitizedValue: null);
    }

    final trimmedNotes = notes.trim();

    // Check length
    if (trimmedNotes.length > maxNotesLength) {
      return ValidationResult(
        false,
        'Notes are too long (max $maxNotesLength characters)',
      );
    }

    // Sanitize HTML and dangerous characters
    final sanitized = _sanitizeText(trimmedNotes);

    return ValidationResult(true, 'Valid notes', sanitizedValue: sanitized);
  }

  /// Validates and sanitizes tags
  static ValidationResult validateTags(List<String>? tags) {
    if (tags == null || tags.isEmpty) {
      return ValidationResult(true, 'Valid tags', sanitizedValue: <String>[]);
    }

    // Check count
    if (tags.length > maxTagsCount) {
      return ValidationResult(false, 'Too many tags (max $maxTagsCount)');
    }

    final sanitizedTags = <String>[];

    for (final tag in tags) {
      final trimmedTag = tag.trim();

      if (trimmedTag.isEmpty) continue;

      // Check individual tag length
      if (trimmedTag.length > maxTagLength) {
        return ValidationResult(
          false,
          'Tag "$trimmedTag" is too long (max $maxTagLength characters)',
        );
      }

      // Sanitize tag
      final sanitized = _sanitizeText(trimmedTag);
      if (sanitized.isNotEmpty) {
        sanitizedTags.add(sanitized);
      }
    }

    return ValidationResult(true, 'Valid tags', sanitizedValue: sanitizedTags);
  }

  /// Validates API token format
  static ValidationResult validateApiToken(String? token) {
    if (token == null || token.trim().isEmpty) {
      return ValidationResult(false, 'API token cannot be empty');
    }

    final trimmedToken = token.trim();

    // Basic token format validation (adjust based on your API token format)
    if (trimmedToken.length < 16) {
      return ValidationResult(false, 'API token is too short');
    }

    if (trimmedToken.length > 512) {
      return ValidationResult(false, 'API token is too long');
    }

    // Check for suspicious characters
    if (trimmedToken.contains('<') ||
        trimmedToken.contains('>') ||
        trimmedToken.contains('"') ||
        trimmedToken.contains("'")) {
      return ValidationResult(false, 'API token contains invalid characters');
    }

    return ValidationResult(
      true,
      'Valid API token',
      sanitizedValue: trimmedToken,
    );
  }

  /// Sanitizes text by removing HTML tags and dangerous characters
  static String _sanitizeText(String input) {
    // Remove HTML tags
    String sanitized = input.replaceAll(RegExp(r'<[^>]*>'), '');

    // Remove dangerous characters and escape sequences
    sanitized = sanitized.replaceAll(RegExp(r'[<>"\x27]'), '');

    // Remove control characters except basic whitespace
    sanitized = sanitized.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
      '',
    );

    // Normalize whitespace
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return sanitized;
  }

  /// Checks if URL points to localhost or internal network
  static bool _isLocalOrInternalUrl(Uri uri) {
    final host = uri.host.toLowerCase();

    // Check for localhost variants
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }

    // Check for private IP ranges
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.')) {
      return true;
    }

    // Check for .local domains
    if (host.endsWith('.local')) {
      return true;
    }

    return false;
  }

  /// Validates imported HTML content for security issues
  static ValidationResult validateHtmlContent(String htmlContent) {
    if (htmlContent.length > 10 * 1024 * 1024) {
      // 10MB limit
      return ValidationResult(false, 'HTML content is too large');
    }

    // For bookmark imports, we're more lenient since bookmark HTML files
    // often contain event handlers and other attributes that would normally
    // be considered suspicious. We only check for truly dangerous patterns.
    final lowerContent = htmlContent.toLowerCase();

    // Only check for the most dangerous patterns that wouldn't appear in bookmark files
    final dangerousPatterns = [
      'eval(',
      'document.cookie',
      'vbscript:',
      '<iframe',
      '<embed',
      '<object',
    ];

    for (final pattern in dangerousPatterns) {
      if (lowerContent.contains(pattern.toLowerCase())) {
        return ValidationResult(
          false,
          'HTML content contains suspicious patterns',
        );
      }
    }

    return ValidationResult(
      true,
      'Valid HTML content',
      sanitizedValue: htmlContent,
    );
  }

  /// Validates JSON data structure
  static ValidationResult validateJsonData(String jsonContent) {
    if (jsonContent.length > 50 * 1024 * 1024) {
      // 50MB limit
      return ValidationResult(false, 'JSON content is too large');
    }

    try {
      final decoded = jsonDecode(jsonContent);

      // Basic structure validation for bookmark imports
      if (decoded is! Map<String, dynamic>) {
        return ValidationResult(false, 'Invalid JSON structure');
      }

      return ValidationResult(
        true,
        'Valid JSON data',
        sanitizedValue: jsonContent,
      );
    } catch (e) {
      return ValidationResult(false, 'Invalid JSON format: ${e.toString()}');
    }
  }
}

/// Result of validation operation
class ValidationResult {
  final bool isValid;
  final String message;
  final dynamic sanitizedValue;

  ValidationResult(this.isValid, this.message, {this.sanitizedValue});

  @override
  String toString() => 'ValidationResult(isValid: $isValid, message: $message)';
}
