import 'package:cash_radar/features/analytics/analytics_repository.dart';
import 'package:cash_radar/features/analytics/period_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('negative balances convert with symmetric rounding', () {
    final rates = ExchangeRates(
      values: {'AMD': '1', 'RUB': '4.31'},
      asOf: DateTime.utc(2026),
    );
    expect(ExchangeRates.cents('-10.01'), BigInt.from(-1001));
    expect(rates.convert(BigInt.from(-1001), 'RUB', 'AMD'), BigInt.from(-4314));
    expect(rates.convert(BigInt.from(-1), 'RUB', 'AMD'), BigInt.from(-4));
  });
  test(
    'period comparison, six-month trend, archived accounts and original currencies',
    () {
      final rates = ExchangeRates(
        values: {'AMD': '1', 'RUB': '4.31', 'USD': '358'},
        asOf: DateTime.utc(2026),
      );
      final accounts = <Map<String, dynamic>>[
        {
          'id': 'a',
          'name': 'AMD',
          'is_active': true,
          'currency': 'AMD',
          'current_balance': '100.10',
        },
        {
          'id': 'b',
          'name': 'RUB',
          'is_active': true,
          'currency': 'RUB',
          'current_balance': '-10.00',
        },
        {
          'id': 'c',
          'name': 'Archived',
          'is_active': false,
          'currency': 'AMD',
          'current_balance': '999.00',
        },
      ];
      Map<String, dynamic> event(
        String date,
        String acct,
        String category,
        String type,
        String code,
        String amt,
        String accountAmt,
      ) => {
        'transaction_date': date,
        'account_id': acct,
        'category_id': category,
        'category_name': 'Same name',
        'transaction_type': type,
        'currency': code,
        'account_currency': 'AMD',
        'amount': amt,
        'account_amount': accountAmt,
        'operation_count': 1,
      };
      final events = <Map<String, dynamic>>[
        event('2026-10-30', 'a', 'x', 'expense', 'AMD', '1.00', '1.00'),
        event('2026-11-01', 'a', 'x', 'expense', 'USD', '5.00', '2000.00'),
        event('2026-11-02', 'c', 'y', 'expense', 'AMD', '4.00', '4.00'),
        event('2026-11-02', 'a', 'x', 'income', 'AMD', '3.00', '3.00'),
        event('2026-11-03', 'a', 'x', 'expense', 'AMD', '8.00', '8.00'),
      ];
      final report = assemblePeriodReport(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 2),
        currency: 'AMD',
        events: events,
        rawAccounts: accounts,
        rates: rates,
      );
      expect(report.balance, BigInt.from(5700));
      expect(report.current.expense, BigInt.from(200400));
      expect(report.current.income, BigInt.from(300));
      expect(report.previous!.expense, BigInt.from(100));
      expect(dateKey(report.previousStart!), '2026-10-30');
      expect(report.trend['2026-11-01']!.expense, BigInt.from(201200));
      expect(report.currencies['USD']!.expense, BigInt.from(500));
      expect(report.categories.length, 2);
      expect(
        report.accounts.firstWhere((a) => a.id == 'c').turnover.expense,
        BigInt.from(400),
      );
    },
  );
}
