import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'analytics_repository.dart';
import 'period_report.dart';

const _months = [
  'янв',
  'фев',
  'мар',
  'апр',
  'май',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];
String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
String _money(BigInt value, String currency) =>
    '${ExchangeRates.display(value)} $currency';
String _change(BigInt value, String currency) =>
    '${value > BigInt.zero ? '+' : ''}${_money(value, currency)}';

class PeriodAnalytics extends ConsumerStatefulWidget {
  const PeriodAnalytics({
    required this.owner,
    required this.currency,
    required this.month,
    super.key,
  });
  final String owner, currency;
  final DateTime month;
  @override
  ConsumerState<PeriodAnalytics> createState() => _PeriodAnalyticsState();
}

class _PeriodAnalyticsState extends ConsumerState<PeriodAnalytics> {
  late DateTimeRange _range;
  @override
  void initState() {
    super.initState();
    _range = _monthRange(widget.month);
  }

  @override
  void didUpdateWidget(covariant PeriodAnalytics old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner ||
        old.month.year != widget.month.year ||
        old.month.month != widget.month.month) {
      _range = _monthRange(widget.month);
    }
  }

  DateTimeRange _monthRange(DateTime d) => DateTimeRange(
    start: DateTime(d.year, d.month),
    end: DateTime(d.year, d.month + 1, 0),
  );
  Future<void> _selectRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _range,
    );
    if (mounted && selected != null) setState(() => _range = selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = (
      widget.owner,
      dateKey(_range.start),
      dateKey(_range.end),
      widget.currency,
    );
    final report = ref.watch(periodReportProvider(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        Text('Подробная аналитика', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _selectRange,
              icon: const Icon(Icons.date_range),
              label: Text('${_day(_range.start)} — ${_day(_range.end)}'),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _range = _monthRange(widget.month)),
              child: const Text('Выбранный месяц'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        report.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => Column(
            children: [
              const Text('Не удалось загрузить аналитику или курсы валют.'),
              TextButton(
                onPressed: () => ref.invalidate(periodReportProvider(key)),
                child: const Text('Повторить'),
              ),
            ],
          ),
          data: (data) => _content(data),
        ),
      ],
    );
  }

  Widget _content(PeriodReport report) {
    final theme = Theme.of(context), currency = report.currency;
    final previous = report.previous;
    final sortedCategories = report.categories.values.toList()
      ..sort((a, b) => b.turnover.expense.compareTo(a.turnover.expense));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Текущий общий баланс',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _money(report.balance, currency),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Только активные счета · на текущий момент',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Доходы и расходы за период', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Доходы: ${_money(report.current.income, currency)}'),
        Text('Расходы: ${_money(report.current.expense, currency)}'),
        if (previous != null) ...[
          const SizedBox(height: 12),
          Text(
            'Предыдущий период: ${_day(report.previousStart!)} — ${_day(report.previousEnd!)}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            'Доходы: ${_money(previous.income, currency)} · изменение ${_change(report.current.income - previous.income, currency)}',
          ),
          Text(
            'Расходы: ${_money(previous.expense, currency)} · изменение ${_change(report.current.expense - previous.expense, currency)}',
          ),
        ] else
          const Text('Нет данных предыдущего периода в допустимом диапазоне.'),
        const SizedBox(height: 24),
        Text(
          'Динамика расходов по месяцам',
          style: theme.textTheme.titleMedium,
        ),
        Text(
          'Шесть полных месяцев, включая месяц окончания периода',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ..._trend(report, theme),
        const SizedBox(height: 24),
        Text(
          'Расходы по категориям за период',
          style: theme.textTheme.titleMedium,
        ),
        if (sortedCategories.every((c) => c.turnover.expense == BigInt.zero))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Расходов нет'),
          ),
        for (final category in sortedCategories.where(
          (c) => c.turnover.expense > BigInt.zero,
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(category.name),
            trailing: Text(_money(category.turnover.expense, currency)),
          ),
        const SizedBox(height: 16),
        Text('По счетам', style: theme.textTheme.titleMedium),
        Text(
          'Обороты за период; остатки — на текущий момент',
          style: theme.textTheme.bodySmall,
        ),
        if (report.accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Счетов нет'),
          ),
        for (final account in report.accounts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${account.name}${account.active ? '' : ' · архив'}'),
            subtitle: Text(
              'Доходы ${_money(account.turnover.income, currency)} · расходы ${_money(account.turnover.expense, currency)}\n${account.active ? 'Остаток ${_money(account.balance, account.currency)}' : 'Архивный счёт не включён в общий баланс'}',
            ),
          ),
        const SizedBox(height: 16),
        Text('По валютам операций', style: theme.textTheme.titleMedium),
        Text(
          'Оригинальные суммы без пересчёта',
          style: theme.textTheme.bodySmall,
        ),
        if (report.currencies.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Операций нет'),
          ),
        for (final entry in report.currencies.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.key),
            subtitle: Text(
              'Доходы ${_money(entry.value.income, entry.key)} · расходы ${_money(entry.value.expense, entry.key)}',
            ),
          ),
        if (report.ratesAsOf != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Приблизительный пересчёт по текущему безналичному курсу покупки ACBA / Rate.am на ${report.ratesAsOf!.toLocal().toString().substring(0, 16)}; исторические курсы не используются.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  List<Widget> _trend(PeriodReport report, ThemeData theme) {
    final max = report.trend.values.fold(
      BigInt.zero,
      (current, t) => t.expense > current ? t.expense : current,
    );
    return [
      for (final entry in report.trend.entries)
        Builder(
          builder: (context) {
            final date = DateTime.parse(entry.key), value = entry.value.expense;
            final fraction = max == BigInt.zero
                ? 0.0
                : (value.toDouble() / max.toDouble()).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${_months[date.month - 1]} ${date.year}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _money(value, report.currency),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }
}
