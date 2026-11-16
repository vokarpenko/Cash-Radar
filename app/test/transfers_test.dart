import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/transactions/transactions_repository.dart';
import 'package:cash_radar/features/transfers/transfers_repository.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/fake_auth.dart';
import 'transaction_management_test.dart'
    show MemoryTransactions, TransactionTestAccounts;

class _Accounts implements AccountsRepository {
  @override
  Future<List<AccountSummary>> loadAccounts() async => [
    const AccountSummary(id: 'a', name: 'Bank', type: 'bank', currency: 'AMD'),
    const AccountSummary(id: 'b', name: 'Cash', type: 'cash', currency: 'AMD'),
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

class _Transfers implements TransfersRepository {
  @override
  SupabaseClient get client => throw UnimplementedError();
  bool confirmed = false;
  bool failFirst = false;
  final List<String> requestIds = [];
  String? feeValue;
  @override
  Future<List<Map<String, dynamic>>> candidates() async => confirmed
      ? []
      : [
          {
            'debit_id': 'd',
            'credit_id': 'c',
            'debit_account': 'Bank',
            'credit_account': 'Cash',
            'debit_amount': '100',
            'credit_amount': '100',
            'debit_currency': 'AMD',
            'credit_currency': 'AMD',
            'debit_date': '2026-11-01',
            'credit_date': '2026-11-01',
            'exact_amount': true,
          },
        ];
  @override
  Future<List<Map<String, dynamic>>> groups() async => [];
  @override
  Future<void> confirm(
    String debit,
    String credit, {
    String? fee,
    String? debitVersion,
    String? creditVersion,
    String? feeVersion,
  }) async {
    confirmed = true;
  }

  @override
  Future<void> reject(String debit, String credit) async {}
  @override
  Future<void> unlink(String id) async {}
  @override
  Future<void> cash(
    String debit,
    String wallet, {
    String? debitVersion,
  }) async {}
  @override
  Future<void> create({
    required String from,
    required String to,
    required String date,
    required String fromAmount,
    required String toAmount,
    required String fee,
    required String requestId,
    String? description,
  }) async {
    requestIds.add(requestId);
    feeValue = fee;
    if (failFirst && requestIds.length == 1) throw Exception('network');
  }
}

void main() {
  testWidgets('suggested transfer requires explicit confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuth()..active = true;
    addTearDown(auth.controller.close);
    final transfers = _Transfers();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(
            TransactionTestAccounts(),
          ),
          transactionsRepositoryProvider.overrideWithValue(
            MemoryTransactions(),
          ),
          transfersRepositoryProvider.overrideWithValue(transfers),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/transactions');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переводы'));
    await tester.pumpAndSettle();
    expect(find.textContaining('одинаковая сумма'), findsOneWidget);
    await tester.tap(find.text('Это перевод'));
    await tester.pumpAndSettle();
    expect(transfers.confirmed, isFalse);
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(transfers.confirmed, isTrue);
  });
  testWidgets('manual retry keeps the same request id and fee', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuth()..active = true;
    addTearDown(auth.controller.close);
    final transfers = _Transfers()..failFirst = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(_Accounts()),
          transactionsRepositoryProvider.overrideWithValue(
            MemoryTransactions(),
          ),
          transfersRepositoryProvider.overrideWithValue(transfers),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/transactions');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переводы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый перевод'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Со счёта'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank · AMD').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'На счёт'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash · AMD').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Списано AMD'),
      '100',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Комиссия AMD'),
      '2',
    );
    await tester.ensureVisible(find.text('Создать перевод'));
    await tester.tap(find.text('Создать перевод'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось создать перевод'), findsOneWidget);
    await tester.tap(find.text('Создать перевод'));
    await tester.pumpAndSettle();
    expect(transfers.requestIds.length, 2);
    expect(transfers.requestIds[0], transfers.requestIds[1]);
    expect(transfers.feeValue, '2');
  });
  testWidgets('user change closes nested transfer dialogs', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuth()..active = true;
    addTearDown(auth.controller.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(_Accounts()),
          transactionsRepositoryProvider.overrideWithValue(
            MemoryTransactions(),
          ),
          transfersRepositoryProvider.overrideWithValue(_Transfers()),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/transactions');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переводы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый перевод'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNWidgets(2));
    auth.changeUser('other-user');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
