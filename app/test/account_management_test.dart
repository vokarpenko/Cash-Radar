import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/settings/currency_repository.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_auth.dart';

class MemoryAccounts implements AccountsRepository {
  final items = <AccountSummary>[];
  AccountInput? lastInput;
  @override
  Future<List<AccountSummary>> loadAccounts() async => List.of(items);
  @override
  Future<List<Bank>> loadBanks() async => [
    const Bank(id: 'bank-1', name: 'Ameria Bank'),
  ];
  @override
  Future<void> createAccount(AccountInput input) async {
    lastInput = input;
    items.add(
      AccountSummary(
        id: 'account-1',
        name: input.name,
        type: input.type,
        currency: input.currency,
        bankId: input.bankId,
        bankName: input.bankId == null ? null : 'Ameria Bank',
        initialBalance: input.initialBalance,
        currentBalance: input.initialBalance,
      ),
    );
  }

  @override
  Future<void> updateAccount(String id, AccountInput input) async {
    lastInput = input;
    final index = items.indexWhere((a) => a.id == id);
    items[index] = AccountSummary(
      id: id,
      name: input.name,
      type: input.type,
      currency: input.currency,
      bankId: input.bankId,
      bankName: input.bankId == null ? null : 'Ameria Bank',
      initialBalance: input.initialBalance,
      currentBalance: input.initialBalance,
      isActive: items[index].isActive,
    );
  }

  @override
  Future<void> setActive(String id, bool active) async {
    final i = items.indexWhere((a) => a.id == id);
    final a = items[i];
    items[i] = AccountSummary(
      id: a.id,
      name: a.name,
      type: a.type,
      currency: a.currency,
      bankId: a.bankId,
      bankName: a.bankName,
      initialBalance: a.initialBalance,
      currentBalance: a.currentBalance,
      isActive: active,
    );
  }
}

class MemoryCurrency implements CurrencyRepository {
  String value = 'AMD';
  @override
  Future<String> loadBaseCurrency() async => value;
  @override
  Future<void> saveBaseCurrency(String currency) async {
    value = currency;
  }
}

void main() {
  late FakeAuth auth;
  late MemoryAccounts accounts;
  late MemoryCurrency currency;
  setUp(() {
    auth = FakeAuth()..active = true;
    accounts = MemoryAccounts();
    currency = MemoryCurrency();
  });
  tearDown(() => auth.controller.close());

  Future<void> openAccounts(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(accounts),
          currencyRepositoryProvider.overrideWithValue(currency),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/accounts');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creates and edits an exact balance and archives and restores an account',
    (tester) async {
      await openAccounts(tester);
      await tester.tap(find.text('Добавить счёт'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Ameria',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ameria Bank').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Начальный баланс'),
        '1,001',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Начальный баланс'),
            )
            .controller!
            .text,
        '0',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Начальный баланс'),
        '999999999999999999,99',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(accounts.lastInput!.initialBalance, '999999999999999999.99');
      expect(find.text('999999999999999999.99 AMD'), findsOneWidget);
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Новая карта',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Начальный баланс'),
        '-0.01',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Новая карта'), findsOneWidget);
      expect(find.text('-0.01 AMD'), findsOneWidget);
      await tester.tap(find.text('В архив'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Архивировать'));
      await tester.pumpAndSettle();
      expect(find.text('Новая карта'), findsNothing);
      await tester.tap(find.text('Показать архивные'));
      await tester.pumpAndSettle();
      expect(find.text('Новая карта'), findsOneWidget);
      await tester.tap(find.text('Восстановить'));
      await tester.pumpAndSettle();
      expect(accounts.items.single.isActive, isTrue);
    },
  );

  testWidgets('does not retain an account editing dialog after changing user', (
    tester,
  ) async {
    await openAccounts(tester);
    await tester.tap(find.text('Добавить счёт'));
    await tester.pumpAndSettle();
    expect(find.text('Новый счёт'), findsOneWidget);
    auth.changeUser('another-user');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Новый счёт'), findsNothing);
  });

  testWidgets('edits a stored balance with insignificant trailing zeros', (
    tester,
  ) async {
    accounts.items.add(
      const AccountSummary(
        id: 'legacy',
        name: 'Кошелёк',
        type: 'cash',
        currency: 'AMD',
        initialBalance: '12.3400',
        currentBalance: '12.3400',
      ),
    );
    await openAccounts(tester);
    expect(find.text('12.34 AMD'), findsOneWidget);
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    expect(find.text('12.34'), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(accounts.lastInput!.initialBalance, '12.34');
  });

  testWidgets('long names and balances fit a narrow screen', (tester) async {
    await openAccounts(tester);
    await accounts.createAccount(
      const AccountInput(
        name: 'Счёт с очень длинным названием для проверки ширины экрана',
        type: 'cash',
        currency: 'AMD',
        initialBalance: '999999999999999999.99',
      ),
    );
    tester.view.physicalSize = const Size(390, 800);
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/dashboard');
    await tester.pumpAndSettle();
    router.go('/accounts');
    await tester.pumpAndSettle();
    expect(find.text('999999999999999999.99 AMD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves primary currency in settings', (tester) async {
    await openAccounts(tester);
    GoRouter.of(tester.element(find.byType(AppShell))).go('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.text('AMD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    expect(currency.value, 'USD');
    expect(find.text('USD'), findsOneWidget);
  });
}
