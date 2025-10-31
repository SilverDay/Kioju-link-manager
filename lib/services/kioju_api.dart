import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../utils/security_utils.dart';
import '../db.dart';

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

  /// Sets the API token with automatic fallback storage
  /// 
  /// Tries to store the token in secure storage (keychain/credential manager) first.
  /// If secure storage fails (e.g., on macOS without proper entitlements), 
  /// automatically falls back to storing the token in the database config table.
  /// This ensures the token can always be saved, even when secure storage is unavailable.
  /// 
  /// **Security Note:** When using database fallback, the token is stored in plaintext
  /// in the SQLite database, which is less secure than platform keychain storage.
  /// However, the database is still protected by filesystem permissions and is only
  /// used when secure storage is unavailable.

  static Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      // Delete from both secure storage and database
      try {
        await _storage.delete(key: _tokenKey);
      } catch (e) {
        // Ignore secure storage deletion errors
      }
      try {
        await _deleteTokenFromDb();
      } catch (e) {
        // Ignore database deletion errors
      }
      return;
    }

    // Validate token before storing
    final validation = SecurityUtils.validateApiToken(token);
    if (!validation.isValid) {
      throw ArgumentError('Invalid API token: ${validation.message}');
    }

    final sanitizedToken = validation.sanitizedValue as String;

    // Try secure storage first
    bool secureStorageSucceeded = false;
    try {
      await _storage.write(
        key: _tokenKey,
        value: sanitizedToken,
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        wOptions: const WindowsOptions(),
        lOptions: const LinuxOptions(),
      );
      secureStorageSucceeded = true;
    } catch (e) {
      // Secure storage failed, will use database fallback
    }

    // If secure storage failed, use database as fallback
    if (!secureStorageSucceeded) {
      try {
        await _saveTokenToDb(sanitizedToken);
      } catch (e) {
        throw Exception('Failed to save API token to both secure storage and database: $e');
      }
    } else {
      // Secure storage succeeded, ensure database fallback is cleared
      try {
        await _deleteTokenFromDb();
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  static Future<bool> hasToken() async {
    try {
      final token = await _readToken();
      return token != null && token.isNotEmpty;
    } catch (e) {
      // Silent failure - token check should not throw
      return false;
    }
  }

  /// Helper method to read the token with automatic fallback
  /// 
  /// Tries to read from secure storage first, then falls back to database
  /// if secure storage fails or returns null. This ensures token retrieval
  /// works regardless of which storage method was used to save it.
  static Future<String?> _readToken() async {
    // Try secure storage first
    try {
      final token = await _storage.read(
        key: _tokenKey,
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        wOptions: const WindowsOptions(),
        lOptions: const LinuxOptions(),
      );
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      // Secure storage failed, will try database fallback
    }

    // Fallback to database if secure storage failed or returned null
    try {
      return await _readTokenFromDb();
    } catch (e) {
      // Both storage methods failed
      return null;
    }
  }

  /// Saves the API token to the database config table
  /// 
  /// **Security Note:** The token is stored in plaintext in the database.
  /// This method is only used as a fallback when secure storage is unavailable.
  static Future<void> _saveTokenToDb(String token) async {
    final db = await AppDb.instance();
    await db.insert(
      'config',
      {'key': _tokenKey, 'value': token},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Reads the API token from the database config table
  static Future<String?> _readTokenFromDb() async {
    final db = await AppDb.instance();
    final result = await db.query(
      'config',
      where: 'key = ?',
      whereArgs: [_tokenKey],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return null;
  }

  /// Deletes the API token from the database config table
  static Future<void> _deleteTokenFromDb() async {
    final db = await AppDb.instance();
    await db.delete(
      'config',
      where: 'key = ?',
      whereArgs: [_tokenKey],
    );
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
        } else if (key == 'message' || key == 'plan' || key == 'error') {
          // Preserve API response messages and status fields
          sanitized[key] = value;
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
      } else if (value == null) {
        // Preserve null values for API responses
        sanitized[key] = null;
      } else {
        // For any other type, preserve as-is (this includes API response fields)
        sanitized[key] = value;
      }
    }

    return sanitized;
  }

  static Future<List<Map<String, dynamic>>> listLinks({
    int limit = 100,
    int offset = 0,
  }) async {
    // Validate input parameters
    if (limit < 1 || limit > 100) {
      throw ArgumentError('Invalid limit: must be between 1 and 100');
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

  static Future<Map<String, dynamic>> updateLink({
    required String id,
    String? title,
    String? description,
    String? isPrivate,
    List<String>? tags,
  }) async {
    // Validate the ID parameter
    if (id.trim().isEmpty) {
      throw ArgumentError('Link ID cannot be empty');
    }

    final sanitizedId = id.trim().replaceAll(RegExp(r'[<>"\x27]'), '');
    if (sanitizedId.isEmpty) {
      throw ArgumentError('Invalid link ID format');
    }

    // Validate title if provided
    if (title != null) {
      final titleValidation = SecurityUtils.validateTitle(title);
      if (!titleValidation.isValid) {
        throw ArgumentError('Invalid title: ${titleValidation.message}');
      }
    }

    // Validate description if provided
    if (description != null) {
      // Allow empty descriptions to clear them
      if (description.isNotEmpty) {
        final descValidation = SecurityUtils.validateNotes(description);
        if (!descValidation.isValid) {
          throw ArgumentError('Invalid description: ${descValidation.message}');
        }
      }
    }

    // Validate privacy setting if provided
    if (isPrivate != null && isPrivate != '0' && isPrivate != '1') {
      throw ArgumentError('Invalid privacy setting: must be "0" or "1"');
    }

    // Validate tags if provided
    if (tags != null) {
      final tagsValidation = SecurityUtils.validateTags(tags);
      if (!tagsValidation.isValid) {
        throw ArgumentError('Invalid tags: ${tagsValidation.message}');
      }
    }

    final token = await _readToken();

    final form = <String, String>{'action': 'update', 'id': sanitizedId};

    // Add optional parameters only if they are provided
    if (title != null) {
      final titleValidation = SecurityUtils.validateTitle(title);
      if (titleValidation.sanitizedValue != null) {
        form['title'] = titleValidation.sanitizedValue!;
      }
    }

    if (description != null) {
      if (description.isEmpty) {
        form['description'] = ''; // Clear description
      } else {
        final descValidation = SecurityUtils.validateNotes(description);
        if (descValidation.sanitizedValue != null) {
          form['description'] = descValidation.sanitizedValue!;
        }
      }
    }

    if (isPrivate != null) {
      form['is_private'] = isPrivate;
    }

    if (tags != null) {
      final tagsValidation = SecurityUtils.validateTags(tags);
      if (tagsValidation.sanitizedValue != null) {
        form['tags'] = (tagsValidation.sanitizedValue as List<String>).join(
          ',',
        );
      }
    }

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

  static Future<Map<String, dynamic>> checkPremiumStatus() async {
    final token = await _readToken();

    final uri = Uri.parse(
      _baseUrl,
    ).replace(queryParameters: {'action': 'premium_status'});

    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final res = await _secureGet(uri, headers);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      
      final sanitized = _sanitizeApiResponseItem(data);
      
      return sanitized;
    } catch (e) {
      throw Exception('Failed to parse API response: $e');
    }
  }

  /// Test with browser-like request format
  static Future<Map<String, dynamic>> testBrowserLikeRequest() async {
    final token = await _readToken();
    
    if (token == null || token.isEmpty) {
      return {'error': 'No API token found'};
    }

    // Try to mimic exactly what a browser extension would send
    final uri = Uri.parse('https://kioju.de/api/api.php?action=premium_status');
    
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'X-Api-Key': token,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };

    try {
      final client = _createSecureClient();
      final response = await client.get(uri, headers: headers).timeout(_requestTimeout);
      client.close();

      return {
        'status_code': response.statusCode,
        'body': response.body,
        'headers_sent': headers,
        'success': response.statusCode == 200,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Test with a completely different token format/approach
  static Future<Map<String, dynamic>> testAlternativeTokenFormat() async {
    final token = await _readToken();
    
    if (token == null || token.isEmpty) {
      return {'error': 'No API token found'};
    }

    // Try different header formats that might work
    final testCases = [
      {'Authorization': 'Bearer $token'},
      {'Authorization': 'Token $token'},
      {'X-API-Token': token},
      {'X-Auth-Token': token},
      {'Api-Key': token},
      {'X-Api-Key': token}, // Current format
    ];

    final results = <String, dynamic>{};
    
    for (int i = 0; i < testCases.length; i++) {
      final headers = <String, String>{
        'User-Agent': 'KiojuLinkManager/1.0',
        'Content-Type': 'application/x-www-form-urlencoded',
        ...testCases[i],
      };

      try {
        final uri = Uri.parse(_baseUrl).replace(queryParameters: {'action': 'premium_status'});
        final client = _createSecureClient();
        final response = await client.get(uri, headers: headers).timeout(_requestTimeout);
        client.close();

        results['test_${i + 1}_${testCases[i].keys.first}'] = {
          'status_code': response.statusCode,
          'body': response.body,
          'headers': testCases[i],
        };
      } catch (e) {
        results['test_${i + 1}_${testCases[i].keys.first}'] = {
          'error': e.toString(),
          'headers': testCases[i],
        };
      }
    }

    return results;
  }

  /// Test basic API connectivity with current token
  static Future<Map<String, dynamic>> testApiConnection() async {
    final token = await _readToken();
    
    if (token == null || token.isEmpty) {
      return {'error': 'No API token found'};
    }

    // Try the simplest API call first - add action (which should work for any valid token)
    final uri = Uri.parse(_baseUrl);
    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      'X-Api-Key': token,
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    try {
      // Test with a minimal request that should return an error but validate the token
      final client = _createSecureClient();
      final response = await client.post(
        uri, 
        headers: headers, 
        body: {'action': 'test'} // Invalid action, but should validate token first
      ).timeout(_requestTimeout);
      
      client.close();

      return {
        'status_code': response.statusCode,
        'body': response.body,
        'token_accepted': response.statusCode != 401, // 401 means invalid token
        'headers': response.headers.toString(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Analyze token format without hashing
  static Future<Map<String, dynamic>> debugTokenInfo() async {
    final token = await _readToken();
    
    if (token == null || token.isEmpty) {
      return {'error': 'No token found'};
    }
    
    return {
      'token_length': token.length,
      'token_preview': '${token.substring(0, 8)}...',
      'token_full': token,
      'is_valid_hex': RegExp(r'^[0-9a-fA-F]+$').hasMatch(token),
      'character_analysis': _analyzeTokenCharacters(token),
    };
  }

  static Map<String, dynamic> _analyzeTokenCharacters(String token) {
    final chars = token.split('');
    final analysis = <String, dynamic>{};
    
    analysis['total_length'] = chars.length;
    analysis['unique_chars'] = chars.toSet().length;
    analysis['has_uppercase'] = chars.any((c) => c.toUpperCase() == c && c.toLowerCase() != c);
    analysis['has_lowercase'] = chars.any((c) => c.toLowerCase() == c && c.toUpperCase() != c);
    analysis['has_numbers'] = chars.any((c) => '0123456789'.contains(c));
    analysis['invalid_chars'] = chars.where((c) => !'0123456789abcdefABCDEF'.contains(c)).toList();
    
    return analysis;
  }

  // Debug methods removed for production

  static Future<List<Map<String, dynamic>>> searchTags({
    required String query,
    int limit = 10,
  }) async {
    // Validate input parameters
    if (query.trim().isEmpty) {
      throw ArgumentError('Search query cannot be empty');
    }
    if (limit < 1 || limit > 30) {
      throw ArgumentError('Invalid limit: must be between 1 and 30');
    }

    // Use the tag suggestions endpoint
    final uri = Uri.parse(
      'https://kioju.de/api/tag_suggestions.php',
    ).replace(queryParameters: {'q': query.trim(), 'limit': '$limit'});

    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      'X-Requested-With': 'XMLHttpRequest',
    };

    final res = await _secureGet(uri, headers);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true && data['results'] is List) {
        return List<Map<String, dynamic>>.from(data['results']);
      }
      return [];
    } catch (e) {
      throw Exception('Failed to parse tag search response: $e');
    }
  }

  // ============================================================================
  // COLLECTION MANAGEMENT API ENDPOINTS
  // ============================================================================

  /// List all collections for the authenticated user
  static Future<Map<String, dynamic>> listCollections() async {
    final token = await _readToken();

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {'action': 'collections_list'},
    );

    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final res = await _secureGet(uri, headers);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _sanitizeApiResponseItem(data);
    } catch (e) {
      throw Exception('Failed to parse collections list response: $e');
    }
  }

  /// Create a new collection
  static Future<Map<String, dynamic>> createCollection({
    required String name,
    String? description,
    String visibility = 'public',
    List<String>? tags,
  }) async {
    // Validate input
    if (name.trim().isEmpty) {
      throw ArgumentError('Collection name cannot be empty');
    }
    if (name.length > 100) {
      throw ArgumentError('Collection name cannot exceed 100 characters');
    }
    if (description != null && description.length > 2000) {
      throw ArgumentError('Collection description cannot exceed 2000 characters');
    }
    if (!['public', 'private', 'hidden'].contains(visibility)) {
      throw ArgumentError('Invalid visibility setting');
    }

    final token = await _readToken();

    final form = <String, String>{
      'action': 'collections_create',
      'name': name.trim(),
      'visibility': visibility,
    };

    if (description != null && description.trim().isNotEmpty) {
      form['description'] = description.trim();
    }

    if (tags != null && tags.isNotEmpty) {
      form['tags'] = jsonEncode(tags);
    }

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
      throw Exception('Failed to parse create collection response: $e');
    }
  }

  /// Update an existing collection
  static Future<Map<String, dynamic>> updateCollection({
    required String id,
    String? name,
    String? description,
    String? visibility,
    List<String>? tags,
  }) async {
    // Validate ID
    if (id.trim().isEmpty) {
      throw ArgumentError('Collection ID cannot be empty');
    }

    // Validate optional parameters
    if (name != null) {
      if (name.trim().isEmpty) {
        throw ArgumentError('Collection name cannot be empty');
      }
      if (name.length > 100) {
        throw ArgumentError('Collection name cannot exceed 100 characters');
      }
    }

    if (description != null && description.length > 2000) {
      throw ArgumentError('Collection description cannot exceed 2000 characters');
    }

    if (visibility != null && !['public', 'private', 'hidden'].contains(visibility)) {
      throw ArgumentError('Invalid visibility setting');
    }

    final token = await _readToken();

    final form = <String, String>{
      'action': 'collections_update',
      'id': id.trim(),
    };

    if (name != null) {
      form['name'] = name.trim();
    }

    if (description != null) {
      form['description'] = description.trim();
    }

    if (visibility != null) {
      form['visibility'] = visibility;
    }

    if (tags != null) {
      form['tags'] = jsonEncode(tags);
    }

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
      throw Exception('Failed to parse update collection response: $e');
    }
  }

  /// Delete a collection
  static Future<Map<String, dynamic>> deleteCollection({
    required String id,
    String deleteMode = 'move_links',
  }) async {
    // Validate ID
    if (id.trim().isEmpty) {
      throw ArgumentError('Collection ID cannot be empty');
    }

    // Validate delete mode
    if (!['move_links', 'delete_links'].contains(deleteMode)) {
      throw ArgumentError('Invalid delete mode: must be "move_links" or "delete_links"');
    }

    final token = await _readToken();

    final form = <String, String>{
      'action': 'collections_delete',
      'id': id.trim(),
      'delete_mode': deleteMode,
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
      throw Exception('Failed to parse delete collection response: $e');
    }
  }

  /// Assign a link to a collection
  static Future<Map<String, dynamic>> assignLinkToCollection({
    required String linkId,
    String? collectionId,
  }) async {
    // Validate link ID
    if (linkId.trim().isEmpty) {
      throw ArgumentError('Link ID cannot be empty');
    }

    final token = await _readToken();

    final form = <String, String>{
      'action': 'collections_assign_link',
      'link_id': linkId.trim(),
    };

    if (collectionId != null && collectionId.trim().isNotEmpty) {
      form['collection_id'] = collectionId.trim();
    }

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
      throw Exception('Failed to parse assign link response: $e');
    }
  }

  /// Get links within a specific collection
  static Future<Map<String, dynamic>> getCollectionLinks(String collectionId) async {
    // Validate collection ID
    if (collectionId.trim().isEmpty) {
      throw ArgumentError('Collection ID cannot be empty');
    }

    final token = await _readToken();

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'action': 'collections_get_links',
        'id': collectionId.trim(),
      },
    );

    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final res = await _secureGet(uri, headers);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _sanitizeApiResponseItem(data);
    } catch (e) {
      throw Exception('Failed to parse collection links response: $e');
    }
  }

  /// Get uncategorized links (not assigned to any collection)
  static Future<Map<String, dynamic>> getUncategorizedLinks() async {
    final token = await _readToken();

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {'action': 'collections_get_uncategorized'},
    );

    final headers = <String, String>{
      'User-Agent': 'KiojuLinkManager/1.0',
      if (token != null) 'X-Api-Key': token,
    };

    final res = await _secureGet(uri, headers);

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _sanitizeApiResponseItem(data);
    } catch (e) {
      throw Exception('Failed to parse uncategorized links response: $e');
    }
  }
}
