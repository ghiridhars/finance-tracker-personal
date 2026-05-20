/// Authentication service for the Finance Tracker frontend.
/// Manages JWT tokens, login, registration, and auth state.
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Auth state — holds token and username if logged in.
class AuthState {
  final String? token;
  final String? username;
  final bool isRegistered;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.token,
    this.username,
    this.isRegistered = false,
    this.isLoading = true,
    this.error,
  });

  bool get isAuthenticated => token != null;

  AuthState copyWith({
    String? token,
    String? username,
    bool? isRegistered,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      token: token ?? this.token,
      username: username ?? this.username,
      isRegistered: isRegistered ?? this.isRegistered,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier that manages authentication state.
class AuthNotifier extends Notifier<AuthState> {
  static const _tokenKey = 'auth_token';
  static const _usernameKey = 'auth_username';

  @override
  AuthState build() {
    _initAuth();
    return const AuthState(isLoading: true);
  }

  Future<void> _initAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_tokenKey);
      final savedUsername = prefs.getString(_usernameKey);

      // Check if backend has a registered user
      final statusResp = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/auth/status'),
      );
      final isRegistered = statusResp.statusCode == 200 &&
          jsonDecode(statusResp.body)['registered'] == true;

      if (savedToken != null && savedUsername != null) {
        // Validate saved token by calling /api/auth/me
        final meResp = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/auth/me'),
          headers: {'Authorization': 'Bearer $savedToken'},
        );
        if (meResp.statusCode == 200) {
          ApiService.setAuthToken(savedToken); // Apply to ApiClient so all API modules can use it
          state = AuthState(
            token: savedToken,
            username: savedUsername,
            isRegistered: isRegistered,
            isLoading: false,
          );
          return;
        }
      }

      // No valid token — need login
      state = AuthState(
        isRegistered: isRegistered,
        isLoading: false,
      );
    } catch (e) {
      state = AuthState(isLoading: false, error: 'Cannot connect to server');
    }
  }

  Future<void> register(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      if (resp.statusCode != 200) {
        final detail = _extractDetail(resp.body);
        state = state.copyWith(isLoading: false, error: detail);
        return;
      }
      final data = jsonDecode(resp.body);
      await _saveAndApplyToken(data['access_token'], username);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection failed');
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // OAuth2 password flow uses form-encoded body
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
      );
      if (resp.statusCode != 200) {
        final detail = _extractDetail(resp.body);
        state = state.copyWith(isLoading: false, error: detail);
        return;
      }
      final data = jsonDecode(resp.body);
      await _saveAndApplyToken(data['access_token'], username);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection failed');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    ApiService.setAuthToken(null);
    state = AuthState(isRegistered: state.isRegistered, isLoading: false);
  }

  Future<void> _saveAndApplyToken(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_usernameKey, username);
    ApiService.setAuthToken(token);
    state = AuthState(
      token: token,
      username: username,
      isRegistered: true,
      isLoading: false,
    );
  }

  String _extractDetail(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json.containsKey('detail')) {
        return json['detail'].toString();
      }
    } catch (_) {}
    return body;
  }
}

/// Provider for auth state.
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
