import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/analytics/analytics_repository.dart';
import 'package:cash_radar/features/analytics/analytics_format.dart';
import 'package:cash_radar/features/analytics/period_report.dart';
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

class MemoryPeriodReport implements PeriodReportRepository {
  @override
  Future<PeriodReport> load(
    DateTime start,
    DateTime end,
    String currency,
  ) async => PeriodReport(
    start: start,
    end: end,
    currency: currency,
    balance: BigInt.from(12345),
    current: Turnover(expense: BigInt.from(1000)),
    previous: Turnover(expense: BigInt.from(500)),
    previousStart: start.subtract(const Duration(days: 30)),
    previousEnd: start.subtract(const Duration(days: 1)),
    trend: {
      dateKey(DateTime(start.year, start.month, 1)): Turnover(
        expense: BigInt.from(1000),
      ),
    },
    accounts: [
      ReportAccount(
        id: 'a',
        name: 'Карта',
        active: true,
        currency: 'AMD',
        balance: BigInt.from(25000),
        convertedBalance: BigInt.from(25000),
      ),
    ],
    currencies: {'AMD': Turnover(expense: BigInt.from(1000))},
    categories: {},
  );
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
    expect(
      analyticsAmount(BigInt.parse('-123456789')),
      '−1\u00a0234\u00a0567.89',
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
            periodReportRepositoryProvider.overrideWithValue(
              MemoryPeriodReport(),
            ),
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
      expect(find.text('Текущий общий баланс'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Изменить бюджет'));
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
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<bool>),
          matching: find.text('Доходы'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Зарплата'));
      await tester.pumpAndSettle();
      expect(find.text('Зарплата'), findsOneWidget);
      expect(find.text('Еда'), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RUB').last);
      await tester.pumpAndSettle();
      expect(currency.currency, 'RUB');
      expect(find.text('500.00 RUB'), findsWidgets);
      await tester.ensureVisible(find.text('Текущий общий баланс'));
      await tester.pumpAndSettle();
      expect(find.text('Текущий общий баланс'), findsOneWidget);
      expect(find.text('123.45 RUB'), findsOneWidget);
      await tester.ensureVisible(find.text('Карта'));
      await tester.pumpAndSettle();
      expect(find.text('Карта'), findsOneWidget);
      expect(find.text('Остаток'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('analytics cards fit narrow and wide layouts', (tester) async {
    final auth = FakeAuth()..active = true;
    addTearDown(auth.controller.close);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 700);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider.overrideWithValue(MemoryAnalytics()),
          periodReportRepositoryProvider.overrideWithValue(
            MemoryPeriodReport(),
          ),
          currencyRepositoryProvider.overrideWithValue(MemoryCurrency()),
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
    await tester.tap(find.byTooltip('Установить бюджет'));
    await tester.pumpAndSettle();
    expect(find.text('Установить бюджет'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Текущий общий баланс'));
    await tester.pumpAndSettle();
    expect(find.text('Текущий общий баланс'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
