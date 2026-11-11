import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Isolates UI code from the authentication provider.
abstract interface class AuthService {
  bool get hasSession;
  String? get userId;
  Stream<AuthState> get changes;
  Future<bool> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> updatePassword(String password);
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);
  final SupabaseClient _client;

  String get _redirectUrl {
    if (kIsWeb) return '${Uri.base.origin}/';
    return 'io.cashradar.app://auth-callback/';
  }

  String get _recoveryUrl => '$_redirectUrl?recovery=1';

  @override
  bool get hasSession =>
      _client.auth.currentSession != null &&
      !_client.auth.currentSession!.isExpired;

  @override
  String? get userId => hasSession ? _client.auth.currentUser?.id : null;

  @override
  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  @override
  Future<bool> signUp(String email, String password) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: _redirectUrl,
    );
    return response.session != null;
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: _recoveryUrl);

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }
}
