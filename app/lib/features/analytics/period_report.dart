import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_repository.dart';

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime calendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class Turnover {
  Turnover({BigInt? income, BigInt? expense, this.count = 0})
    : income = income ?? BigInt.zero,
      expense = expense ?? BigInt.zero;
  BigInt income, expense;
  int count;
  void add(String type, BigInt value, int number) {
    if (type == 'income') {
      income += value;
    } else {
      expense += value;
    }
    count += number;
  }
}

class ReportAccount {
  ReportAccount({
    required this.id,
    required this.name,
    required this.active,
    required this.currency,
    required this.balance,
    required this.convertedBalance,
  });
  final String id, name, currency;
  final bool active;
  final BigInt balance, convertedBalance;
  final Turnover turnover = Turnover();
}

class ReportCategory {
  ReportCategory(this.name);
  final String name;
  final Turnover turnover = Turnover();
}

class PeriodReport {
  PeriodReport({
    required this.start,
    required this.end,
    required this.currency,
    required this.balance,
    required this.current,
    required this.previous,
    required this.previousStart,
    required this.previousEnd,
    required this.trend,
    required this.accounts,
    required this.currencies,
    required this.categories,
    this.ratesAsOf,
  });
  final DateTime start, end;
  final String currency;
  final BigInt balance;
  final Turnover current;
  final Turnover? previous;
  final DateTime? previousStart, previousEnd;
  final Map<String, Turnover> trend;
  final List<ReportAccount> accounts;
  final Map<String, Turnover> currencies;
  final Map<String, ReportCategory> categories;
  final DateTime? ratesAsOf;
}

abstract interface class PeriodReportRepository {
  Future<PeriodReport> load(DateTime start, DateTime end, String currency);
}

class SupabasePeriodReportRepository implements PeriodReportRepository {
  SupabasePeriodReportRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> _activity(
    DateTime start,
    DateTime end,
  ) async {
    final rows = <Map<String, dynamic>>[];
    const size = 500;
    for (var offset = 0; ; offset += size) {
      final page = await client
          .rpc(
            'period_analytics_activity',
            params: {'p_start': dateKey(start), 'p_end': dateKey(end)},
          )
          .range(offset, offset + size - 1);
      final batch = (page as List).cast<Map<String, dynamic>>();
      rows.addAll(batch);
      if (batch.length < size) return rows;
    }
  }

  Future<List<Map<String, dynamic>>> _accounts() async {
    final rows = <Map<String, dynamic>>[];
    const size = 500;
    for (var offset = 0; ; offset += size) {
      final page = await client
          .from('account_balances')
          .select('id,name,currency,current_balance,is_active')
          .order('id')
          .range(offset, offset + size - 1);
      rows.addAll(page);
      if (page.length < size) return rows;
    }
  }

  @override
  Future<PeriodReport> load(
    DateTime start,
    DateTime end,
    String currency,
  ) async {
    start = calendarDay(start);
    end = calendarDay(end);
    if (start.isAfter(end)) throw ArgumentError('Invalid period');
    final days = end.difference(start).inDays + 1;
    final previousEnd = start.subtract(const Duration(days: 1));
    final previousStart = previousEnd.subtract(Duration(days: days - 1));
    final hasPrevious = previousStart.year >= 1900;
    final trendStart = DateTime.utc(end.year, end.month - 5, 1);
    final trendEnd = DateTime.utc(end.year, end.month + 1, 0);
    final safeTrendStart = trendStart.year < 1900
        ? DateTime.utc(1900)
        : trendStart;
    var from = start.isBefore(safeTrendStart) ? start : safeTrendStart;
    if (hasPrevious && previousStart.isBefore(from)) from = previousStart;
    final to = end.isAfter(trendEnd) ? end : trendEnd;
    final results = await Future.wait([_activity(from, to), _accounts()]);
    final events = results[0], rawAccounts = results[1];
    final needsRates =
        events.any(
          (e) => e['currency'] != currency && e['account_currency'] != currency,
        ) ||
        rawAccounts.any(
          (a) =>
              a['is_active'] == true &&
              a['currency'] != currency &&
              ExchangeRates.cents(a['current_balance'] as String) !=
                  BigInt.zero,
        );
    ExchangeRates? rates;
    if (needsRates) {
      rates = await RateQuoteCache.load(client);
    }
    return assemblePeriodReport(
      start: start,
      end: end,
      currency: currency,
      events: events,
      rawAccounts: rawAccounts,
      rates: rates,
    );
  }
}

PeriodReport assemblePeriodReport({
  required DateTime start,
  required DateTime end,
  required String currency,
  required List<Map<String, dynamic>> events,
  required List<Map<String, dynamic>> rawAccounts,
  ExchangeRates? rates,
}) {
  start = calendarDay(start);
  end = calendarDay(end);
  if (start.isAfter(end)) throw ArgumentError('Invalid period');
  final days = end.difference(start).inDays + 1;
  final previousEnd = start.subtract(const Duration(days: 1));
  final previousStart = previousEnd.subtract(Duration(days: days - 1));
  final hasPrevious = previousStart.year >= 1900;
  BigInt convert(BigInt value, String from) =>
      from == currency || value == BigInt.zero
      ? value
      : rates!.convert(value, from, currency);
  final accounts = <String, ReportAccount>{};
  for (final a in rawAccounts) {
    final active = a['is_active'] as bool,
        original = ExchangeRates.cents(a['current_balance'] as String),
        code = a['currency'] as String;
    accounts[a['id'] as String] = ReportAccount(
      id: a['id'] as String,
      name: a['name'] as String,
      active: active,
      currency: code,
      balance: original,
      convertedBalance: active ? convert(original, code) : BigInt.zero,
    );
  }
  final current = Turnover(), previous = hasPrevious ? Turnover() : null;
  final trend = <String, Turnover>{};
  for (var i = 0; i < 6; i++) {
    final month = DateTime.utc(end.year, end.month - 5 + i, 1);
    if (month.year >= 1900 && month.year <= 2100) {
      trend[dateKey(month)] = Turnover();
    }
  }
  final currencies = <String, Turnover>{};
  final categories = <String, ReportCategory>{};
  for (final event in events) {
    final date = calendarDay(
      DateTime.parse(event['transaction_date'] as String),
    );
    final type = event['transaction_type'] as String,
        source = event['currency'] as String,
        accountCurrency = event['account_currency'] as String;
    final original = ExchangeRates.cents(event['amount'] as String);
    final converted = source == currency
        ? original
        : accountCurrency == currency
        ? ExchangeRates.cents(event['account_amount'] as String)
        : convert(original, source);
    final count = (event['operation_count'] as num).toInt();
    trend[dateKey(DateTime.utc(date.year, date.month, 1))]?.add(
      type,
      converted,
      count,
    );
    if (hasPrevious &&
        !date.isBefore(previousStart) &&
        !date.isAfter(previousEnd)) {
      previous!.add(type, converted, count);
    }
    if (date.isBefore(start) || date.isAfter(end)) continue;
    current.add(type, converted, count);
    currencies.putIfAbsent(source, Turnover.new).add(type, original, count);
    categories
        .putIfAbsent(
          event['category_id'] as String,
          () => ReportCategory(event['category_name'] as String),
        )
        .turnover
        .add(type, converted, count);
    accounts[event['account_id']]?.turnover.add(type, converted, count);
  }
  final sortedAccounts =
      accounts.values.where((a) => a.active || a.turnover.count > 0).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  return PeriodReport(
    start: start,
    end: end,
    currency: currency,
    balance: accounts.values
        .where((a) => a.active)
        .fold(BigInt.zero, (sum, a) => sum + a.convertedBalance),
    current: current,
    previous: previous,
    previousStart: hasPrevious ? previousStart : null,
    previousEnd: hasPrevious ? previousEnd : null,
    trend: trend,
    accounts: sortedAccounts,
    currencies: currencies,
    categories: categories,
    ratesAsOf: rates?.asOf,
  );
}

final periodReportRepositoryProvider = Provider<PeriodReportRepository>(
  (ref) => SupabasePeriodReportRepository(Supabase.instance.client),
  dependencies: const [],
);
final periodReportProvider = FutureProvider.autoDispose
    .family<PeriodReport, (String, String, String, String)>(
      (ref, key) => ref
          .watch(periodReportRepositoryProvider)
          .load(DateTime.parse(key.$2), DateTime.parse(key.$3), key.$4),
      dependencies: [periodReportRepositoryProvider],
      retry: (_, _) => null,
    );
