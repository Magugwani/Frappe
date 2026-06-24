import 'package:flutter/foundation.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';

/// Session state — drives router navigation.
/// `checking` is ONLY set during app-startup checkSession().
/// login() and logout() never change status to a "loading" variant —
/// they use the separate [isSubmitting] flag instead.
enum AuthStatus {
  initial,       // App just launched, no check done yet
  checking,      // checkSession() in progress (router shows splash)
  authenticated, // Valid session confirmed
  unauthenticated, // No session / logged out
}

class AuthProvider extends ChangeNotifier {
  final AuthService _service = AuthService();

  AuthStatus _status = AuthStatus.initial;
  AuthUser? _user;
  String? _errorMessage;

  /// True only while a login or logout HTTP request is in flight.
  /// Does NOT affect the router — only the button/spinner in the UI.
  bool _isSubmitting = false;

  AuthStatus get status => _status;
  AuthUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isSubmitting => _isSubmitting;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _user != null;

  // ── App startup: check stored session ─────────────────────────────────────
  //
  // State machine:
  //   initial → checking → authenticated  (router: /splash → /dashboard)
  //   initial → checking → unauthenticated (router: /splash → /login)

  Future<void> checkSession() async {
    debugPrint('[AUTH] checkSession() started');
    _status = AuthStatus.checking;
    notifyListeners();

    try {
      final user = await _service.getStoredSession();
      if (user != null) {
        _user = user;
        _status = AuthStatus.authenticated;
        debugPrint('[AUTH] Session restored — role: ${user.role}');
      } else {
        _status = AuthStatus.unauthenticated;
        debugPrint('[AUTH] No valid session — directing to login');
      }
    } catch (e) {
      // Any unexpected error defaults to unauthenticated so the app
      // never gets stuck on splash.
      _status = AuthStatus.unauthenticated;
      debugPrint('[AUTH] checkSession error (defaulting to unauthenticated): $e');
    }

    notifyListeners();
    debugPrint('[AUTH] checkSession() completed — status: $_status');
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  //
  // Uses _isSubmitting only — _status never goes to a loading state.
  // This guarantees the router redirect never fires for the login form.
  //
  //   success: _status → authenticated  → router redirects to dashboard
  //   failure: _status → unauthenticated → router stays on /login, snackbar shown

  Future<bool> login(String email, String password) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _service.login(email, password);
      _user = user;
      _status = AuthStatus.authenticated;
      _isSubmitting = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.unauthenticated;
      _isSubmitting = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Unable to connect. Please check your connection and try again.';
      _status = AuthStatus.unauthenticated;
      _isSubmitting = false;
      debugPrint('[AUTH] Login unexpected error: $e');
      notifyListeners();
      return false;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    debugPrint('[AUTH] Logout started');
    _isSubmitting = true;
    notifyListeners();

    await _service.logout();

    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    _isSubmitting = false;
    debugPrint('[AUTH] Logout complete');
    notifyListeners();
  }
}
