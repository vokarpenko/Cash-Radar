import 'dart:async';

import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/auth/auth_screen.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_auth.dart';

class ControlledAccounts implements AccountsRepository {
  final requests = <Completer<List<AccountSummary>>>[];
  @override
  Future<List<AccountSummary>> loadAccounts() {
    final request = Completer<List<AccountSummary>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  late FakeAuth auth;
  late ControlledAccounts accounts;
  setUp(() {
    auth = FakeAuth()..active = true;
    accounts = ControlledAccounts();
  });
  tearDown(() => auth.controller.close());

  Widget app() => ProviderScope(
    overrides: [accountsRepositoryProvider.overrideWithValue(accounts)],
    child: CashRadarApp(auth: auth),
  );

  testWidgets('navigates between sections on a wide screen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Добро пожаловать в CashRadar'), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/transactions');
    await tester.pumpAndSettle();
    expect(find.text('История операций'), findsOneWidget);
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Управление приложением и доступом'), findsOneWidget);
    router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('Добро пожаловать в CashRadar'), findsOneWidget);
  });

  testWidgets('protects a direct route and restores it after login', (
    tester,
  ) async {
    auth.active = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(AuthScreen)));
    router.go('/accounts');
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    await auth.signIn('person@example.com', 'password123');
    await tester.pump();
    expect(accounts.requests, hasLength(1));
    accounts.requests.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Счетов пока нет'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/accounts');
  });

  testWidgets('ignores an external redirect after login', (tester) async {
    auth.active = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(AuthScreen)));
    router.go('/login?from=https%3A%2F%2Fexample.com');
    await tester.pumpAndSettle();
    await auth.signIn('person@example.com', 'password123');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/dashboard');
  });

  testWidgets('shows navigation on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Операции'));
    await tester.pumpAndSettle();
    expect(find.text('История операций'), findsOneWidget);
  });

  testWidgets('accounts show loading, error, retry and real values', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/accounts');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    accounts.requests.single.completeError(Exception('private details'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить счета'), findsOneWidget);
    expect(find.textContaining('private details'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(accounts.requests, hasLength(2));
    accounts.requests.last.complete([
      const AccountSummary(
        id: '1',
        name: 'Мой кошелёк',
        type: 'cash',
        currency: 'AMD',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Мой кошелёк'), findsOneWidget);
    expect(find.text('AMD'), findsOneWidget);
  });

  testWidgets('accounts show an empty state', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/accounts');
    await tester.pump();
    accounts.requests.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Счетов пока нет'), findsOneWidget);
  });

  testWidgets('hides previous account data immediately when identity changes', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/accounts');
    await tester.pump();
    accounts.requests.single.complete([
      const AccountSummary(
        id: '1',
        name: 'Личный счёт A',
        type: 'cash',
        currency: 'AMD',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Личный счёт A'), findsOneWidget);
    auth.changeUser('different-user');
    await tester.pump();
    expect(find.text('Личный счёт A'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(accounts.requests, hasLength(2));
    accounts.requests.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Счетов пока нет'), findsOneWidget);
  });
}
