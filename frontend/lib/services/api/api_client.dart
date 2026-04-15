/// Shared HTTP client utilities for all API modules.
/// Provides auth token management, common headers, and error extraction.
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thrown when the server returns 401 — signals that the auth token is
/// invalid or expired and the user should be redirected to the login screen.
class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Session expired. Please log in again.']);

  @override
  String toString() => message;
}

class ApiClient {
  /// Internal base URL — synced from AppSettings at startup.
  static String _baseUrl = 'http://127.0.0.1:8080';
  static String get baseUrl => _baseUrl;

  /// Default request timeout.
  static const Duration timeout = Duration(seconds: 30);

  /// Update the base URL (called from AppSettingsNotifier).
  static void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// JWT token — set after login.
  static String? _authToken;

  /// Set the auth token for all subsequent requests.
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Standard headers including auth token.
  static Map<String, String> get headers {
    final h = <String, String>{};
    if (_authToken != null) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  /// Standard headers including auth token and JSON content type.
  static Map<String, String> get jsonHeaders {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_authToken != null) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  /// Check a response for 401 and throw [UnauthorizedException] if so.
  /// Call this after every authenticated request.
  static void checkAuth(http.Response response) {
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
  }

  /// Extract error detail from FastAPI error response JSON.
  static String extractErrorDetail(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json.containsKey('detail')) {
        return json['detail'].toString();
      }
    } catch (_) {}
    return body;
  }
}
