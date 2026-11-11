import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/accounts_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/imports/imports_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/transactions_screen.dart';
import 'app_shell.dart';
import 'auth_navigation.dart';

const _protectedPaths = {
  '/dashboard',
  '/accounts',
  '/transactions',
  '/imports',
  '/settings',
};

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authNavigationProvider);
  final router = GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;
      if (auth.hasSession && auth.recovery) {
        return path == '/auth/recovery' ? null : '/auth/recovery';
      }
      if (!auth.hasSession) {
        if (path == '/login') return null;
        final from = _protectedPaths.contains(path)
            ? '?from=${Uri.encodeQueryComponent(path)}'
            : '';
        return '/login$from';
      }
      if (path == '/login') {
        final from = state.uri.queryParameters['from'];
        return from != null && _protectedPaths.contains(from)
            ? from
            : '/dashboard';
      }
      if (path == '/' || path == '/auth/recovery') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => AuthScreen(auth: auth.auth),
      ),
      GoRoute(
        path: '/auth/recovery',
        builder: (context, state) => AuthScreen(
          auth: auth.auth,
          initialMode: AuthMode.updatePassword,
          onPasswordUpdated: auth.finishRecovery,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/imports',
            builder: (context, state) => const ImportsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Страница не найдена.'),
            TextButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('На главную'),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
}, dependencies: [authNavigationProvider]);
