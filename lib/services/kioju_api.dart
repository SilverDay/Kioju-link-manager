import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class KiojuApi {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'api_token';
  static const _baseUrl = 'https://kioju.de/api/api.php'; // Hardcoded API URL

  static Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  static Future<bool> hasToken() async =>
      (await _storage.read(key: _tokenKey)) != null;

  static Future<List<Map<String, dynamic>>> listLinks({
    int limit = 100,
    int offset = 0,
  }) async {
    final token = await _storage.read(key: _tokenKey);

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'action': 'list',
        'limit': '$limit',
        'offset': '$offset',
      },
    );

    final res = await http.get(
      uri,
      headers: {if (token != null) 'X-Api-Key': token},
    );

    if (res.statusCode != 200) {
      throw Exception('Kioju listLinks failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    if (data is Map && data['links'] is List) {
      return List<Map<String, dynamic>>.from(data['links']);
    }
    return [];
  }

  static Future<Map<String, dynamic>> addLink({
    required String url,
    String? title,
    List<String>? tags,
    String isPrivate = '1',
    String captureDescription = '1',
  }) async {
    final token = await _storage.read(key: _tokenKey);

    final form = {
      'action': 'add',
      'url': url,
      'is_private': isPrivate,
      'capture_description': captureDescription,
      if (title != null && title.isNotEmpty) 'title': title,
      if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
    };

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        if (token != null) 'X-Api-Key': token,
      },
      body: form,
    );

    if (res.statusCode != 200) {
      throw Exception('Kioju addLink failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> deleteLink(String id) async {
    final token = await _storage.read(key: _tokenKey);

    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        if (token != null) 'X-Api-Key': token,
      },
      body: {'action': 'delete', 'id': id},
    );

    if (res.statusCode != 200) {
      throw Exception('Kioju deleteLink failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
