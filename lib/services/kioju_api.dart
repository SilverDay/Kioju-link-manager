import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../utils/security_utils.dart';

/// Custom exception for rate limiting
class RateLimitException implements Exception {
  final String message;
  final Duration? retryAfter;

  const RateLimitException(this.message, {this.retryAfter});

  @override
  String toString() => 'RateLimitException: $message';
}

/// Custom exception for authentication errors
class AuthenticationException implements Exception {
  final String message;

  const AuthenticationException(this.message);

  @override
  String toString() => 'AuthenticationException: $message';
}

/// Custom exception for authorization errors
class AuthorizationException implements Exception {
  final String message;

  const AuthorizationException(this.message);

  @override
  String toString() => 'AuthorizationException: $message';
}

/// Custom exception for general API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

class KiojuApi {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'api_token';
  static const _baseUrl = 'https://kioju.de/api/api.php'; // Hardcoded API URL

  // Security configurations
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // Rate limiting configurations
  static const Duration _maxRateLimitWait = Duration(minutes: 5);
  static const Duration _defaultRateLimitDelay = Duration(seconds: 60);
  static DateTime? _lastRateLimitTime;
  static Duration? _rateLimitCooldown;

  static Future<void> setToken(String? token) async {
    try {
      if (token == null || token.isEmpty) {
        await _storage.delete(key: _tokenKey);
      } else {
        // Validate token before storing
        final validation = SecurityUtils.validateApiToken(token);
        if (!validation.isValid) {
          throw ArgumentError('Invalid API token: ${validation.message}');
        }
        
        // For macOS, we might need to configure secure storage options
        await _storage.write(
          key: _tokenKey, 
          value: validation.sanitizedValue,
          aOptions: const AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: const IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          mOptions: const MacOsOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          wOptions: const WindowsOptions(),
          lOptions: const LinuxOptions(),
        );
      }
    } catch (e) {
      // Re-throw with more context for debugging
      throw Exception('Failed to save API token: $e');
    }
  }

  static Future<bool> hasToken() async {
    try {
      final token = await _readToken();
      return token != null && token.isNotEmpty;
    } catch (e) {
      print('Error checking for token: $e');
      return false;
    }
  }

  /// Helper method to read the token with consistent configuration
  static Future<String?> _readToken() async {
    try {
      return await _storage.read(
        key: _tokenKey,
        aOptions: const AndroidOptions(
          encryptedSharedPreferences: true,
        ),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        wOptions: const WindowsOptions(),
        lOptions: const LinuxOptions(),
      );
    } catch (e) {
      print('Error reading token from secure storage: $e');
      return null;
    }
  }

  /// Gets rate limit status information
  static Map<String, dynamic> getRateLimitStatus() {
    if (_lastRateLimitTime == null || _rateLimitCooldown == null) {
      return {
        'isRateLimited': false,
        'canMakeRequest': true,
        'message': 'No rate limits active',
      };
    }

    final now = DateTime.now();
    final cooldownEnd = _lastRateLimitTime!.add(_rateLimitCooldown!);
    final isInCooldown = now.isBefore(cooldownEnd);

    if (isInCooldown) {
      final remainingTime = cooldownEnd.difference(now);
      return {
        'isRateLimited': true,
        'canMakeRequest': false,
        'remainingSeconds': remainingTime.inSeconds,
        'message':
            'Rate limited. ${remainingTime.inSeconds} seconds remaining.',
      };
    } else {
      return {
        'isRateLimited': false,
        'canMakeRequest': true,
        'message': 'Rate limit cooldown has expired',
      };
    }
  }

  /// Creates a secure HTTP client with timeout and security headers
  static http.Client _createSecureClient() {
    final client = http.Client();
    return client;
  }

  /// Checks if we're currently in a rate limit cooldown period
  static bool _isInRateLimitCooldown() {
    if (_lastRateLimitTime == null || _rateLimitCooldown == null) {
      return false;
    }

    final now = DateTime.now();
    final cooldownEnd = _lastRateLimitTime!.add(_rateLimitCooldown!);
    return now.isBefore(cooldownEnd);
  }

  /// Parses rate limit information from response headers
  static Duration? _parseRateLimitDelay(http.Response response) {
    // Check for common rate limit headers
    final retryAfter = response.headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        return Duration(seconds: seconds);
      }
    }

    final rateLimitReset = response.headers['x-ratelimit-reset'];
    if (rateLimitReset != null) {
      final resetTime = int.tryParse(rateLimitReset);
      if (resetTime != null) {
        final resetDateTime = DateTime.fromMillisecondsSinceEpoch(
          resetTime * 1000,
        );
        final delay = resetDateTime.difference(DateTime.now());
        if (delay.isNegative) return null;
        return delay;
      }
    }

    return null;
  }

  /// Updates rate limit state when a 429 response is received
  static void _handleRateLimit(http.Response response) {
    _lastRateLimitTime = DateTime.now();
    final delay = _parseRateLimitDelay(response);
    _rateLimitCooldown = delay ?? _defaultRateLimitDelay;

    // Cap the wait time to prevent excessive delays
    if (_rateLimitCooldown!.compareTo(_maxRateLimitWait) > 0) {
      _rateLimitCooldown = _maxRateLimitWait;
    }
  }

  /// Performs a secure HTTP GET request with retries and rate limit handling
  static Future<http.Response> _secureGet(
    Uri uri,
    Map<String, String> headers,
  ) async {
    // Check if we're in a rate limit cooldown
    if (_isInRateLimitCooldown()) {
      final waitTime = _lastRateLimitTime!
          .add(_rateLimitCooldown!)
          .difference(DateTime.now());
      throw RateLimitException(
        'Rate limited. Please wait ${waitTime.inSeconds} seconds.',
      );
    }

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final client = _createSecureClient();
        try {
          final response = await client
              .get(uri, headers: headers)
              .timeout(_requestTimeout);

          // Handle different response codes
          if (response.statusCode == 200) {
            _validateResponseSecurity(response);
            return response;
          } else if (response.statusCode == 429) {
            // Rate limited
            _handleRateLimit(response);
            throw RateLimitException(
              'Rate limited. Please wait ${_rateLimitCooldown!.inSeconds} seconds.',
              retryAfter: _rateLimitCooldown!,
            );
          } else if (response.statusCode == 401) {
            throw AuthenticationException('Invalid or expired API token');
          } else if (response.statusCode == 403) {
            throw AuthorizationException(
              'Access forbidden. Check your API token permissions.',
            );
          } else if (response.statusCode >= 500 && attempt < _maxRetries) {
            // Retry on server errors
            await Future.delayed(_retryDelay);
            continue;
          } else {
            throw ApiException(
              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
              statusCode: response.statusCode,
            );
          }
        } finally {
          client.close();
        }
      } catch (e) {
        if (e is RateLimitException ||
            e is AuthenticationException ||
            e is AuthorizationException) {
          rethrow; // Don't retry these errors
        }
        if (attempt == _maxRetries) rethrow;
        await Future.delayed(_retryDelay);
      }
    }
    throw Exception('Failed after $_maxRetries attempts');
  }

  /// Performs a secure HTTP POST request with retries and rate limit handling
  static Future<http.Response> _securePost(
    Uri uri,
    Map<String, String> headers,
    dynamic body,
  ) async {
    // Check if we're in a rate limit cooldown
    if (_isInRateLimitCooldown()) {
      final waitTime = _lastRateLimitTime!
          .add(_rateLimitCooldown!)
          .difference(DateTime.now());
      throw RateLimitException(
        'Rate limited. Please wait ${waitTime.inSeconds} seconds.',
      );
    }

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final client = _createSecureClient();
        try {
          final response = await client
              .post(uri, headers: headers, body: body)
              .timeout(_requestTimeout);

          // Handle different response codes
          if (response.statusCode == 200) {
            _validateResponseSecurity(response);
            return response;
          } else if (response.statusCode == 429) {
            // Rate limited
            _handleRateLimit(response);
            throw RateLimitException(
              'Rate limited. Please wait ${_rateLimitCooldown!.inSeconds} seconds.',
              retryAfter: _rateLimitCooldown!,
            );
          } else if (response.statusCode == 401) {
            throw AuthenticationException('Invalid or expired API token');
          } else if (response.statusCode == 403) {
            throw AuthorizationException(
              'Access forbidden. Check your API token permissions.',
            );
          } else if (response.statusCode >= 500 && attempt < _maxRetries) {
            // Retry on server errors
            await Future.delayed(_retryDelay);
            continue;
          } else {
            throw ApiException(
              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
              statusCode: response.statusCode,
            );
          }
        } finally {
          client.close();
        }
      } catch (e) {
        if (e is RateLimitException ||
            e is AuthenticationException ||
            e is AuthorizationException) {
          rethrow; // Don't retry these errors
        }
        if (attempt == _maxRetries) rethrow;
        await Future.delayed(_retryDelay);
      }
    }
    throw Exception('Failed after $_maxRetries attempts');
  }

  /// Validates response for security issues
  static void _validateResponseSecurity(http.Response response) {
    // Check content length
    if (response.body.length > 10 * 1024 * 1024) {
      // 10MB limit
      throw Exception('Response too large');
    }

    // Check for suspicious content in response
    final body = response.body.toLowerCase();
    if (body.contains('<script') || body.contains('javascript:')) {
      throw Exception('Suspicious content in response');
    }
  }

  /// Sanitizes a list of API response objects
  static List<Map<String, dynamic>> _sanitizeApiResponseList(
    List<Map<String, dynamic>> data,
  ) {
    return data.map((item) => _sanitizeApiResponseItem(item)).toList();
  }

  /// Sanitizes a single API response object
  static Map<String, dynamic> _sanitizeApiResponseItem(
    Map<String, dynamic> item,
  ) {
    final sanitized = <String, dynamic>{};

    for (final entry in item.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is String) {
        // Validate and sanitize string values
        if (key == 'url' || key == 'link') {
          final validation = SecurityUtils.validateUrl(value);
          if (validation.isValid) {
            sanitized[key] = validation.sanitizedValue;
          }
        } else if (key == 'title') {
          final validation = SecurityUtils.validateTitle(value);
          if (validation.isValid && validation.sanitizedValue != null) {
            sanitized[key] = validation.sanitizedValue;
          }
        } else if (key == 'notes' || key == 'description') {
          final validation = SecurityUtils.validateNotes(value);
          if (validation.isValid && validation.sanitizedValue != null) {
            sanitized[key] = validation.sanitizedValue;
          }
        } else {
          // For other string fields, apply basic sanitization
          final cleaned = value.replaceAll(RegExp(r'[<>"\x27]'), '').trim();
          if (cleaned.isNotEmpty) {
            sanitized[key] = cleaned;
          }
        }
      } else if (value is num || value is bool) {
        // Numbers and booleans are safe
        sanitized[key] = value;
      } else if (value is List) {
        // Handle lists (like tags)
        final cleanedList = <dynamic>[];
        for (final item in value) {
          if (item is String) {
            final cleaned = item.replaceAll(RegExp(r'[<>"\x27]'), '').trim();
            if (cleaned.isNotEmpty) {
              cleanedList.add(cleaned);
            }
          } else if (item is Map<String, dynamic>) {
            cleanedList.add(_sanitizeApiResponseItem(item));
          }
        }
        if (cleanedList.isNotEmpty) {
          sanitized[key] = cleanedList;
        }
      } else if (value is Map<String, dynamic>) {
        // Recursively sanitize nested objects
        sanitized[key] = _sanitizeApiResponseItem(value);
      }
    }

    return sanitized;
  }

  static Future<List<Map<String, dynamic>>> listLinks({
    int limit = 100,
    int offset = 0,
  }) async {
    // Validate input parameters
    if (limit < 1 || limit > 1000) {
      throw ArgumentError('Invalid limit: must be between 1 and 1000');
    }
    if (offset < 0) {
      throw ArgumentError('Invalid offset: must be non-negative');
    }

    final token = await _readToken();

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'action': 'list',
        'limit': '$limit',
        'offset': '$offset',
      },
    );

    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final res = await _secureGet(uri, headers);

    try {
      final data = jsonDecode(res.body);
      if (data is List) {
        return _sanitizeApiResponseList(List<Map<String, dynamic>>.from(data));
      }
      if (data is Map && data['links'] is List) {
        return _sanitizeApiResponseList(
          List<Map<String, dynamic>>.from(data['links']),
        );
      }
      return [];
    } catch (e) {
      throw Exception('Failed to parse API response: $e');
    }
  }

  static Future<Map<String, dynamic>> addLink({
    required String url,
    String? title,
    List<String>? tags,
    String isPrivate = '1',
    String captureDescription = '1',
  }) async {
    // Validate all inputs before making the request
    final urlValidation = SecurityUtils.validateUrl(url);
    if (!urlValidation.isValid) {
      throw ArgumentError('Invalid URL: ${urlValidation.message}');
    }

    final titleValidation = SecurityUtils.validateTitle(title);
    if (!titleValidation.isValid) {
      throw ArgumentError('Invalid title: ${titleValidation.message}');
    }

    final tagsValidation = SecurityUtils.validateTags(tags);
    if (!tagsValidation.isValid) {
      throw ArgumentError('Invalid tags: ${tagsValidation.message}');
    }

    // Validate privacy setting
    if (isPrivate != '0' && isPrivate != '1') {
      throw ArgumentError('Invalid privacy setting: must be "0" or "1"');
    }

    final token = await _readToken();

    final form = {
      'action': 'add',
      'url': urlValidation.sanitizedValue,
      'is_private': isPrivate,
      'capture_description': captureDescription,
      if (titleValidation.sanitizedValue != null)
        'title': titleValidation.sanitizedValue,
      if (tagsValidation.sanitizedValue?.isNotEmpty == true)
        'tags': (tagsValidation.sanitizedValue as List<String>).join(','),
    };

    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final res = await _securePost(Uri.parse(_baseUrl), headers, form);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _sanitizeApiResponseItem(data);
    } catch (e) {
      throw Exception('Failed to parse API response: $e');
    }
  }

  static Future<Map<String, dynamic>> deleteLink(String id) async {
    // Validate the ID parameter
    if (id.trim().isEmpty) {
      throw ArgumentError('Link ID cannot be empty');
    }

    final sanitizedId = id.trim().replaceAll(RegExp(r'[<>"\x27]'), '');
    if (sanitizedId.isEmpty) {
      throw ArgumentError('Invalid link ID format');
    }

    final token = await _readToken();

    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final form = {'action': 'delete', 'id': sanitizedId};

    final res = await _securePost(Uri.parse(_baseUrl), headers, form);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _sanitizeApiResponseItem(data);
    } catch (e) {
      throw Exception('Failed to parse API response: $e');
    }
  }
}
