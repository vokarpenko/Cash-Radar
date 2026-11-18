import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/analytics/analytics_repository.dart';
import 'package:cash_radar/features/settings/currency_repository.dart';
import 'package:cash_radar/features/transactions/transactions_repository.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'support/fake_auth.dart';
import 'transaction_management_test.dart' show MemoryTransactions;

class MemoryCurrency implements CurrencyRepository {
  String currency = 'AMD';
  @override
  Future<String> loadBaseCurrency() async => currency;
  @override
  Future<void> saveBaseCurrency(String value) async {
    currency = value;
  }
}

class MemoryAnalytics implements AnalyticsRepository {
  String? savedCategory, savedAmount, savedMonth, savedCurrency;
  @override
  Future<MonthlyAnalytics> load(String month, String currency) async =>
      MonthlyAnalytics(
        currency: currency,
        rows: [
          AnalyticsRow(
            categoryId: 'food',
            name: 'Еда',
            type: 'expense',
            count: 2,
            spent: BigInt.from(12000),
            limit: BigInt.from(10000),
            limitCurrency: 'AMD',
            limitOriginal: '100',
          ),
          AnalyticsRow(
            categoryId: 'salary',
            name: 'Зарплата',
            type: 'income',
            count: 1,
            spent: BigInt.from(50000),
          ),
        ],
      );
  @override
  Future<void> saveBudget(
    String categoryId,
    String month,
    String currency,
    String? amount,
  ) async {
    savedCategory = categoryId;
    savedMonth = month;
    savedCurrency = currency;
    savedAmount = amount;
  }
}

void main() {
  test('fixed-point conversion keeps exact cents and rounds once', () {
    final rates = ExchangeRates(
      values: {'AMD': '1', 'RUB': '4.31', 'USD': '358'},
      asOf: DateTime.utc(2026),
    );
    expect(
      rates.convert(ExchangeRates.cents('100'), 'RUB', 'AMD'),
      BigInt.from(43100),
    );
    expect(
      rates.convert(ExchangeRates.cents('1'), 'USD', 'RUB'),
      BigInt.from(8306),
    );
    expect(
      ExchangeRates.display(ExchangeRates.cents('999999999999999999.99')),
      '999999999999999999.99',
    );
    expect(
      () => rates.convert(BigInt.one, 'EUR', 'AMD'),
      throwsFormatException,
    );
  });
  testWidgets(
    'analytics presents budget progress, income, currency and editing on mobile',
    (tester) async {
      final auth = FakeAuth()..active = true;
      addTearDown(auth.controller.close);
      final budgets = MemoryAnalytics();
      final currency = MemoryCurrency();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsRepositoryProvider.overrideWithValue(budgets),
            currencyRepositoryProvider.overrideWithValue(currency),
            transactionsRepositoryProvider.overrideWithValue(
              MemoryTransactions(),
            ),
          ],
          child: CashRadarApp(auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(AppShell))).go('/analytics');
      await tester.pumpAndSettle();
      expect(find.text('Аналитика'), findsWidgets);
      expect(find.textContaining('Превышение'), findsWidgets);
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Еда'), findsOneWidget);
      await tester.tap(find.byTooltip('Изменить бюджет'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Лимит на месяц'),
        '250',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(budgets.savedCategory, 'food');
      expect(budgets.savedAmount, '250');
      expect(budgets.savedCurrency, 'AMD');
      await tester.tap(find.text('Доходы'));
      await tester.pumpAndSettle();
      expect(find.text('Зарплата'), findsOneWidget);
      expect(find.text('Еда'), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RUB').last);
      await tester.pumpAndSettle();
      expect(currency.currency, 'RUB');
      expect(find.text('500.00 RUB'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
