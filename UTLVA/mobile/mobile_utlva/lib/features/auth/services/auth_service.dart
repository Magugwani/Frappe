import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../models/auth_user.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  // ── Platform-aware secure storage ─────────────────────────────────────────
  // AndroidOptions are applied only on Android.
  // Web uses default IndexedDB storage (no Android-specific options).
  static FlutterSecureStorage get _storage {
    if (kIsWeb) {
      return const FlutterSecureStorage();
    }
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
  }

  static const _keyAccess = 'utlva_access_token';
  static const _keyRefresh = 'utlva_refresh_token';

  // ── Safe storage read with 5-second timeout ───────────────────────────────
  // Any storage error or hang returns null — never blocks startup.
  static Future<String?> _safeRead(String key) async {
    try {
      return await _storage
          .read(key: key)
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[AUTH] Storage read timeout — key: $key');
        return null;
      });
    } catch (e) {
      debugPrint('[AUTH] Storage read error — key: $key — $e');
      return null;
    }
  }

  static Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[AUTH] Storage write error — key: $key — $e');
    }
  }

  static Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[AUTH] Storage delete error — key: $key — $e');
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<AuthUser> login(String email, String password) async {
    debugPrint('[AUTH] Redirecting login — email: $email');
    final response = await http
        .post(
          Uri.parse(AppConfig.authLogin),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      await _safeWrite(_keyAccess, body['access'] as String);
      await _safeWrite(_keyRefresh, body['refresh'] as String);
      debugPrint('[AUTH] Login successful — role: ${body['role']}');
      return AuthUser.fromJson(body);
    }

    final detail = body['detail'] ??
        (body['non_field_errors'] as List?)?.first ??
        'Login failed';
    debugPrint('[AUTH] Login failed — $detail');
    throw AuthException(detail.toString());
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      final refresh = await _safeRead(_keyRefresh);
      final access = await _safeRead(_keyAccess);
      if (refresh != null && access != null) {
        await http
            .post(
              Uri.parse(AppConfig.authLogout),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $access',
              },
              body: jsonEncode({'refresh': refresh}),
            )
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint('[AUTH] Logout request error (ignored): $e');
    } finally {
      await _clearTokens();
    }
  }

  // ── Session check ─────────────────────────────────────────────────────────

  Future<AuthUser?> getStoredSession() async {
    debugPrint('[AUTH] Checking session');

    final access = await _safeRead(_keyAccess);
    if (access == null) {
      debugPrint('[AUTH] No token');
      return null;
    }

    debugPrint('[AUTH] Token found — verifying with server');

    try {
      final response = await http
          .get(
            Uri.parse(AppConfig.authVerify),
            headers: {'Authorization': 'Bearer $access'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('[AUTH] Token valid');
        return AuthUser.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      debugPrint('[AUTH] Token expired — attempting refresh');
      final newAccess = await _refreshAccessToken();
      if (newAccess == null) {
        debugPrint('[AUTH] Refresh failed — clearing tokens');
        await _clearTokens();
        return null;
      }

      final retry = await http
          .get(
            Uri.parse(AppConfig.authVerify),
            headers: {'Authorization': 'Bearer $newAccess'},
          )
          .timeout(const Duration(seconds: 10));

      if (retry.statusCode == 200) {
        debugPrint('[AUTH] Refresh successful');
        return AuthUser.fromJson(
          jsonDecode(retry.body) as Map<String, dynamic>,
        );
      }

      await _clearTokens();
      return null;
    } catch (e) {
      debugPrint('[AUTH] Session verify error: $e');
      return null;
    }
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  Future<String?> _refreshAccessToken() async {
    final refresh = await _safeRead(_keyRefresh);
    if (refresh == null) return null;

    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.authRefresh),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess = body['access'] as String;
        await _safeWrite(_keyAccess, newAccess);
        if (body['refresh'] != null) {
          await _safeWrite(_keyRefresh, body['refresh'] as String);
        }
        return newAccess;
      }
    } catch (e) {
      debugPrint('[AUTH] Refresh token error: $e');
    }

    await _clearTokens();
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns a valid access token, transparently refreshing it when it is
  /// expired or within 60 seconds of expiry.  Every API service calls this
  /// before attaching the Bearer header — no service needs its own retry logic.
  Future<String?> get accessToken async {
    final stored = await _safeRead(_keyAccess);
    if (stored == null) return null;
    if (_isExpiredOrNearExpiry(stored)) {
      debugPrint('[AUTH] Access token expiring — refreshing silently');
      return _refreshAccessToken();
    }
    return stored;
  }

  /// Decode the JWT payload and return true if the token expires within 60 s.
  static bool _isExpiredOrNearExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final padded = base64.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64.decode(padded))) as Map;
      final exp = payload['exp'];
      if (exp == null) return true;
      final expiry = DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
      return DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 60)));
    } catch (_) {
      return false; // if we can't decode, let the server decide
    }
  }

  Future<void> _clearTokens() async {
    await _safeDelete(_keyAccess);
    await _safeDelete(_keyRefresh);
  }
}
