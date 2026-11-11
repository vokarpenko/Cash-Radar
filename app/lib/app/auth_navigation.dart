import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/accounts/accounts_repository.dart';
import '../features/auth/auth_service.dart';
import '../features/settings/currency_repository.dart';
import '../features/transactions/transactions_repository.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => throw StateError('AuthService is not configured'),
  dependencies: const [],
);
final initialRecoveryProvider = Provider<bool>(
  (ref) => false,
  dependencies: const [],
);

class AuthNavigation extends ChangeNotifier {
  AuthNavigation(
    this.auth, {
    required bool initialRecovery,
    required this.onIdentityChanged,
  }) : hasSession = auth.hasSession,
       userId = auth.userId,
       recovery = initialRecovery && auth.hasSession {
    _subscription = auth.changes.listen(
      _onChange,
      onError: (Object error, StackTrace stack) {
        hasError = true;
        notifyListeners();
      },
    );
  }

  final AuthService auth;
  final VoidCallback onIdentityChanged;
  late final StreamSubscription<AuthState> _subscription;
  bool hasSession;
  String? userId;
  bool recovery;
  bool hasError = false;

  void _onChange(AuthState state) {
    final valid = state.session != null && !state.session!.isExpired;
    final nextId = valid ? state.session!.user.id : null;
    if (userId != nextId) {
      userId = nextId;
      onIdentityChanged();
    }
    hasSession = valid;
    if (state.event == AuthChangeEvent.passwordRecovery) recovery = true;
    if (state.event == AuthChangeEvent.signedOut) recovery = false;
    hasError = false;
    notifyListeners();
  }

  void finishRecovery() {
    recovery = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

final authNavigationProvider = Provider<AuthNavigation>(
  (ref) {
    final controller = AuthNavigation(
      ref.watch(authServiceProvider),
      initialRecovery: ref.watch(initialRecoveryProvider),
      onIdentityChanged: () {
        ref.invalidate(accountsProvider);
        ref.invalidate(baseCurrencyProvider);
        ref.invalidate(transactionsProvider);
        ref.invalidate(transactionCategoriesProvider);
      },
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    authServiceProvider,
    initialRecoveryProvider,
    accountsProvider,
    baseCurrencyProvider,
    transactionsProvider,
    transactionCategoriesProvider,
  ],
);
