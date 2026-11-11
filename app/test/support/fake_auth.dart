import 'dart:async';

import 'package:cash_radar/features/auth/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuth implements AuthService {
  final controller = StreamController<AuthState>.broadcast(sync: true);
  Session session = Session(
    accessToken: 'test-token',
    tokenType: 'bearer',
    user: const User(
      id: 'test-user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '',
    ),
  );
  bool active = false;
  String? requestedEmail;
  String? passwordValue;

  @override
  bool get hasSession => active;
  @override
  String? get userId => active ? session.user.id : null;
  @override
  Stream<AuthState> get changes => controller.stream;

  @override
  Future<bool> signUp(String email, String password) async {
    requestedEmail = email;
    passwordValue = password;
    return false;
  }

  @override
  Future<void> signIn(String email, String password) async {
    requestedEmail = email;
    active = true;
    controller.add(AuthState(AuthChangeEvent.signedIn, session));
  }

  @override
  Future<void> signOut() async {
    active = false;
    controller.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Future<void> resetPassword(String email) async => requestedEmail = email;

  @override
  Future<void> updatePassword(String password) async =>
      passwordValue = password;

  void changeUser(String id) {
    session = Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    active = true;
    controller.add(AuthState(AuthChangeEvent.signedIn, session));
  }
}
