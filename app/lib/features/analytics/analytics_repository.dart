import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fixed-point arithmetic in hundredths; exchange rates are AMD per unit.
class ExchangeRates {
  ExchangeRates({required this.values, required this.asOf});
  final Map<String, String> values;
  final DateTime asOf;

  static BigInt _scaled(String value, int scale) {
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
      throw const FormatException('Invalid decimal');
    }
    final parts = value.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > scale &&
        fraction.substring(scale).contains(RegExp(r'[1-9]'))) {
      throw const FormatException('Too much precision');
    }
    return BigInt.parse(parts[0]) * BigInt.from(10).pow(scale) +
        BigInt.parse((fraction.padRight(scale, '0')).substring(0, scale));
  }

  static BigInt cents(String amount) => _scaled(amount, 2);
  static String display(BigInt value) {
    final negative = value.isNegative;
    final absolute = value.abs();
    return '${negative ? '−' : ''}${absolute ~/ BigInt.from(100)}.${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
  }

  BigInt convert(BigInt cents, String from, String to) {
    if (from == to) return cents;
    final source = values[from], target = values[to];
    if (source == null || target == null) {
      throw const FormatException('Missing currency rate');
    }
    final numerator = cents * _scaled(source, 8);
    final denominator = _scaled(target, 8);
    if (denominator <= BigInt.zero) {
      throw const FormatException('Invalid exchange rate');
    }
    return (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  }
}

class AnalyticsRow {
  AnalyticsRow({
    required this.categoryId,
    required this.name,
    required this.type,
    required this.count,
    required this.spent,
    this.limit,
    this.limitCurrency,
    this.limitOriginal,
  });
  final String categoryId, name, type;
  final int count;
  final BigInt spent;
  final BigInt? limit;
  final String? limitCurrency, limitOriginal;
}

class MonthlyAnalytics {
  MonthlyAnalytics({
    required this.rows,
    required this.currency,
    this.ratesAsOf,
  });
  final List<AnalyticsRow> rows;
  final String currency;
  final DateTime? ratesAsOf;
}

abstract interface class AnalyticsRepository {
  Future<MonthlyAnalytics> load(String month, String currency);
  Future<void> saveBudget(
    String categoryId,
    String month,
    String currency,
    String? amount,
  );
}

class SupabaseAnalyticsRepository implements AnalyticsRepository {
  SupabaseAnalyticsRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> _pages(
    String function,
    String month,
  ) async {
    final result = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var start = 0; ; start += pageSize) {
      final page = await client
          .rpc(function, params: {'p_month': month})
          .range(start, start + pageSize - 1);
      final rows = (page as List).cast<Map<String, dynamic>>();
      result.addAll(rows);
      if (rows.length < pageSize) return result;
    }
  }

  @override
  Future<MonthlyAnalytics> load(String month, String currency) async {
    final raw = await Future.wait([
      _pages('monthly_analytics_activity', month),
      _pages('effective_monthly_budgets', month),
    ]);
    final activity = raw[0], budgets = raw[1];
    final needRates =
        activity.any(
          (row) =>
              row['currency'] != currency &&
              row['account_currency'] != currency,
        ) ||
        budgets.any((row) => row['currency'] != currency);
    ExchangeRates? rates;
    if (needRates) {
      final response = await client.functions.invoke('exchange-rates');
      final data = response.data as Map<String, dynamic>;
      final values = (data['rates'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      );
      rates = ExchangeRates(
        values: values,
        asOf: DateTime.parse(data['asOf'] as String),
      );
    }
    final amounts = <String, BigInt>{};
    final counts = <String, int>{};
    final names = <String, String>{};
    final types = <String, String>{};
    for (final row in activity) {
      final id = row['category_id'] as String;
      final originalCurrency = row['currency'] as String;
      final accountCurrency = row['account_currency'] as String;
      final type = row['transaction_type'] as String;
      final key = '$type:$id';
      final BigInt amount;
      if (originalCurrency == currency) {
        amount = ExchangeRates.cents(row['amount'] as String);
      } else if (accountCurrency == currency) {
        amount = ExchangeRates.cents(row['account_amount'] as String);
      } else {
        amount = rates!.convert(
          ExchangeRates.cents(row['amount'] as String),
          originalCurrency,
          currency,
        );
      }
      amounts[key] = (amounts[key] ?? BigInt.zero) + amount;
      counts[key] =
          (counts[key] ?? 0) + (row['operation_count'] as num).toInt();
      names[key] = row['category_name'] as String;
      types[key] = type;
    }
    final limits = <String, Map<String, dynamic>>{};
    for (final row in budgets) {
      final key = 'expense:${row['category_id']}';
      limits[key] = row;
      names[key] = row['category_name'] as String;
      types[key] = 'expense';
    }
    final rows =
        names.keys.map((key) {
          final budget = limits[key];
          final limitCurrency = budget?['currency'] as String?;
          final original = budget?['amount'] as String?;
          final rawLimit = original == null
              ? null
              : ExchangeRates.cents(original);
          final limit = rawLimit == null
              ? null
              : limitCurrency == currency
              ? rawLimit
              : rates!.convert(rawLimit, limitCurrency!, currency);
          return AnalyticsRow(
            categoryId: key.substring(key.indexOf(':') + 1),
            name: names[key]!,
            type: types[key]!,
            count: counts[key] ?? 0,
            spent: amounts[key] ?? BigInt.zero,
            limit: limit,
            limitCurrency: limitCurrency,
            limitOriginal: original,
          );
        }).toList()..sort((a, b) {
          final amount = b.spent.compareTo(a.spent);
          return amount != 0 ? amount : a.name.compareTo(b.name);
        });
    return MonthlyAnalytics(
      rows: rows,
      currency: currency,
      ratesAsOf: rates?.asOf,
    );
  }

  @override
  Future<void> saveBudget(
    String categoryId,
    String month,
    String currency,
    String? amount,
  ) async {
    await client.rpc(
      'save_budget_version',
      params: {
        'p_category_id': categoryId,
        'p_effective_month': month,
        'p_currency': currency,
        'p_amount': amount,
      },
    );
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => SupabaseAnalyticsRepository(Supabase.instance.client),
  dependencies: const [],
);
final monthlyAnalyticsProvider = FutureProvider.autoDispose
    .family<MonthlyAnalytics, (String, String, String)>(
      (ref, key) => ref.watch(analyticsRepositoryProvider).load(key.$2, key.$3),
      dependencies: [analyticsRepositoryProvider],
      retry: (_, _) => null,
    );
