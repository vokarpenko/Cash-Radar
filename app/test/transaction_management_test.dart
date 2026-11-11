import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/transactions/transactions_repository.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'support/fake_auth.dart';

class TransactionTestAccounts implements AccountsRepository {
  @override
  Future<List<AccountSummary>> loadAccounts() async => [
    const AccountSummary(id: 'a1', name: 'Cash', type: 'cash', currency: 'AMD'),
  ];
  @override
  Future<List<Bank>> loadBanks() async => [];
  @override
  Future<void> createAccount(AccountInput input) async {}
  @override
  Future<void> updateAccount(String id, AccountInput input) async {}
  @override
  Future<void> setActive(String id, bool active) async {}
}

class MemoryTransactions implements TransactionsRepository {
  final List<TransactionEntry> entries = [];
  TransactionInput? lastInput;
  @override
  Future<List<TransactionCategory>> loadCategories() async => [
    const TransactionCategory(id: 'food', name: 'Еда', kind: 'expense'),
    const TransactionCategory(id: 'salary', name: 'Зарплата', kind: 'income'),
  ];
  @override
  Future<List<TransactionEntry>> loadTransactions() async => List.of(entries);
  TransactionEntry entry(String id, TransactionInput input) => TransactionEntry(
    id: id,
    accountId: input.accountId,
    accountName: 'Cash',
    accountActive: true,
    categoryId: input.categoryId,
    categoryName: input.type == 'expense' ? 'Еда' : 'Зарплата',
    type: input.type,
    date: input.date,
    amount: input.amount,
    currency: input.currency,
    accountAmount: input.accountAmount,
    accountCurrency: input.accountCurrency,
    description: input.description,
  );
  @override
  Future<void> createTransaction(TransactionInput input) async {
    lastInput = input;
    entries.add(entry('t1', input));
  }

  @override
  Future<void> updateTransaction(String id, TransactionInput input) async {
    lastInput = input;
    entries[entries.indexWhere((e) => e.id == id)] = entry(id, input);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    entries.removeWhere((e) => e.id == id);
  }
}

void main() {
  late FakeAuth auth;
  late MemoryTransactions repository;
  setUp(() {
    auth = FakeAuth()..active = true;
    repository = MemoryTransactions();
  });
  tearDown(() => auth.controller.close());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(
            TransactionTestAccounts(),
          ),
          transactionsRepositoryProvider.overrideWithValue(repository),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/transactions');
    await tester.pumpAndSettle();
  }

  Finder dropdown(int index) => find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      )
      .at(index);
  testWidgets(
    'creates, edits and deletes a foreign currency expense with confirmation',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Добавить операцию'));
      await tester.pumpAndSettle();
      await tester.tap(dropdown(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash · AMD').last);
      await tester.pumpAndSettle();
      await tester.tap(dropdown(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Еда').last);
      await tester.pumpAndSettle();
      await tester.tap(dropdown(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма операции'),
        '12,34',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма по счёту (AMD)'),
        '5000.01',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Описание (необязательно)'),
        'Завтрак',
      );
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repository.lastInput!.amount, '12.34');
      expect(repository.lastInput!.accountAmount, '5000.01');
      expect(find.text('Завтрак'), findsOneWidget);
      expect(find.text('−12.34 EUR'), findsOneWidget);
      expect(find.text('По счёту: −5000.01 AMD'), findsOneWidget);
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма по счёту (AMD)'),
        '4999',
      );
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repository.lastInput!.accountAmount, '4999');
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(repository.entries, hasLength(1));
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Удалить'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.entries, isEmpty);
    },
  );
  testWidgets('creates an income with a matching category and account amount', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Добавить операцию'));
    await tester.pumpAndSettle();
    await tester.tap(dropdown(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Доход').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdown(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash · AMD').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdown(2));
    await tester.pumpAndSettle();
    expect(find.text('Еда'), findsNothing);
    await tester.tap(find.text('Зарплата').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Сумма операции'),
      '12.01',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repository.lastInput!.type, 'income');
    expect(repository.lastInput!.accountAmount, '12.01');
    expect(find.text('+12.01 AMD'), findsOneWidget);
  });

  testWidgets('operation form fits a narrow screen', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить операцию'));
    await tester.pumpAndSettle();
    await tester.tap(dropdown(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash · AMD').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdown(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Еда').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Сумма операции'),
      '999999999999999999.99',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repository.lastInput!.amount, '999999999999999999.99');
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters operations by type and currency', (tester) async {
    repository.entries.add(
      repository.entry(
        't1',
        const TransactionInput(
          accountId: 'a1',
          categoryId: 'food',
          type: 'expense',
          date: '2026-11-10',
          amount: '3',
          currency: 'EUR',
          accountAmount: '100',
          accountCurrency: 'AMD',
          description: 'Покупка',
        ),
      ),
    );
    repository.entries.add(
      repository.entry(
        't2',
        const TransactionInput(
          accountId: 'a1',
          categoryId: 'salary',
          type: 'income',
          date: '2026-11-11',
          amount: '10',
          currency: 'AMD',
          accountAmount: '10',
          accountCurrency: 'AMD',
          description: 'Выплата',
        ),
      ),
    );
    await open(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Доход').last);
    await tester.pumpAndSettle();
    expect(find.text('Выплата'), findsOneWidget);
    expect(find.text('Покупка'), findsNothing);
    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR').last);
    await tester.pumpAndSettle();
    expect(find.text('Покупка'), findsOneWidget);
    expect(find.text('Выплата'), findsNothing);
  });

  testWidgets('edits a stored operation with insignificant trailing zeros', (
    tester,
  ) async {
    repository.entries.add(
      repository.entry(
        'legacy',
        const TransactionInput(
          accountId: 'a1',
          categoryId: 'food',
          type: 'expense',
          date: '2026-11-10',
          amount: '12.3400',
          currency: 'AMD',
          accountAmount: '12.3400',
          accountCurrency: 'AMD',
          description: 'Ранее сохранено',
        ),
      ),
    );
    await open(tester);
    expect(find.text('−12.34 AMD'), findsOneWidget);
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    expect(find.text('12.34'), findsOneWidget);
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repository.lastInput!.amount, '12.34');
    expect(repository.lastInput!.accountAmount, '12.34');
  });

  testWidgets(
    'amount fields reject letters and extra decimal digits while typing',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Добавить операцию'));
      await tester.pumpAndSettle();
      await tester.tap(dropdown(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash · AMD').last);
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextFormField, 'Сумма операции');
      await tester.enterText(amount, '1000.22');
      await tester.enterText(amount, '1000.22ыва21');
      expect(tester.widget<TextFormField>(amount).controller!.text, '1000.22');
      await tester.enterText(amount, '1000.223');
      expect(tester.widget<TextFormField>(amount).controller!.text, '1000.22');
      await tester.tap(dropdown(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      final accountAmount = find.widgetWithText(
        TextFormField,
        'Сумма по счёту (AMD)',
      );
      await tester.enterText(accountAmount, '25,50');
      await tester.enterText(accountAmount, '25,50abc');
      expect(
        tester.widget<TextFormField>(accountAmount).controller!.text,
        '25,50',
      );
    },
  );

  testWidgets('rejects zero and invalid precision', (tester) async {
    await open(tester);
    await tester.tap(find.text('Добавить операцию'));
    await tester.pumpAndSettle();
    await tester.tap(dropdown(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash · AMD').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdown(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Еда').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Сумма операции'),
      '0.001',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Введите положительную сумму'), findsOneWidget);
    expect(repository.entries, isEmpty);
  });
  testWidgets(
    'searches and resets filters and protects the form on user switch',
    (tester) async {
      await repository.createTransaction(
        const TransactionInput(
          accountId: 'a1',
          categoryId: 'food',
          type: 'expense',
          date: '2026-11-10',
          amount: '25',
          currency: 'AMD',
          accountAmount: '25',
          accountCurrency: 'AMD',
          description: 'Кофе',
        ),
      );
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Поиск'), 'пицца');
      await tester.pumpAndSettle();
      expect(find.text('Операции не найдены'), findsOneWidget);
      await tester.tap(find.text('Сбросить фильтры'));
      await tester.pumpAndSettle();
      expect(find.text('Кофе'), findsOneWidget);
      await tester.tap(find.text('Добавить операцию'));
      await tester.pumpAndSettle();
      auth.changeUser('different-user');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Новая операция'), findsNothing);
    },
  );
}
