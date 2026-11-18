import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_format.dart';
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
    '${analyticsAmount(value)} $currency';
String _change(BigInt value, String currency) =>
    '${value > BigInt.zero ? '+' : ''}${_money(value, currency)}';

class PeriodAnalytics extends ConsumerStatefulWidget {
  const PeriodAnalytics({
    required this.owner,
    required this.currency,
    required this.month,
    required this.monthlyOverview,
    super.key,
  });
  final String owner, currency;
  final DateTime month;
  final Widget monthlyOverview;
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
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (MediaQuery.sizeOf(context).width >= 560)
              Text('Период отчёта', style: theme.textTheme.titleSmall),
            OutlinedButton.icon(
              onPressed: _selectRange,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('${_day(_range.start)} — ${_day(_range.end)}'),
            ),
            if (dateKey(_range.start) !=
                    dateKey(_monthRange(widget.month).start) ||
                dateKey(_range.end) != dateKey(_monthRange(widget.month).end))
              TextButton(
                onPressed: () =>
                    setState(() => _range = _monthRange(widget.month)),
                child: const Text('Выбранный месяц'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        report.when(
          loading: () => Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
              widget.monthlyOverview,
            ],
          ),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Panel(
                child: Column(
                  children: [
                    const Text(
                      'Не удалось загрузить аналитику или курсы валют.',
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(periodReportProvider(key)),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              widget.monthlyOverview,
            ],
          ),
          data: _content,
        ),
      ],
    );
  }

  Widget _content(PeriodReport report) {
    final theme = Theme.of(context), currency = report.currency;
    final previous = report.previous;
    final sortedCategories = report.categories.values.toList()
      ..sort((a, b) => b.turnover.expense.compareTo(a.turnover.expense));
    final categoryList = sortedCategories
        .where((c) => c.turnover.expense > BigInt.zero)
        .toList();
    final previousPeriod = previous == null
        ? null
        : '${_day(report.previousStart!)} — ${_day(report.previousEnd!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 850
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final cards = [
              _MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Текущий общий баланс',
                value: _money(report.balance, currency),
                detail: 'Только активные счета · на текущий момент',
              ),
              _MetricCard(
                icon: Icons.south_west,
                label: 'Доходы за период',
                value: _money(report.current.income, currency),
                detail: previous == null
                    ? 'Нет предыдущего периода'
                    : 'Было ${_money(previous.income, currency)} · ${_change(report.current.income - previous.income, currency)}',
                secondary: previousPeriod,
              ),
              _MetricCard(
                icon: Icons.north_east,
                label: 'Расходы за период',
                value: _money(report.current.expense, currency),
                detail: previous == null
                    ? 'Нет предыдущего периода'
                    : 'Было ${_money(previous.expense, currency)} · ${_change(report.current.expense - previous.expense, currency)}',
                secondary: previousPeriod,
              ),
            ];
            if (cols == 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var start = 0; start < cards.length; start += cols) ...[
                  if (start > 0) const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < cols; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          Expanded(
                            child: start + column < cards.length
                                ? cards[start + column]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        widget.monthlyOverview,
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Динамика расходов', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Шесть полных месяцев, включая месяц окончания периода',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              ..._trend(report, theme),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final width = wide
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Категории за период',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Расходы по выбранным датам',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (categoryList.isEmpty)
                          const _EmptyNote('Расходов за этот период нет'),
                        for (final category in categoryList)
                          _AmountRow(
                            label: category.name,
                            value: _money(category.turnover.expense, currency),
                            icon: Icons.category_outlined,
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Валюты операций',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Оригинальные суммы без пересчёта',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (report.currencies.isEmpty)
                          const _EmptyNote('Операций за этот период нет'),
                        for (final entry in report.currencies.entries)
                          _RecordCard(
                            icon: Icons.currency_exchange,
                            title: entry.key,
                            lines: [
                              _Detail(
                                'Доходы',
                                _money(entry.value.income, entry.key),
                              ),
                              _Detail(
                                'Расходы',
                                _money(entry.value.expense, entry.key),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Счета', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Обороты за период · остатки на текущий момент',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (report.accounts.isEmpty) const _EmptyNote('Счетов пока нет'),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 650;
                  final width = wide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final account in report.accounts)
                        SizedBox(
                          width: width,
                          child: _RecordCard(
                            icon: Icons.account_balance_wallet_outlined,
                            title:
                                '${account.name}${account.active ? '' : ' · архив'}',
                            margin: EdgeInsets.zero,
                            lines: [
                              _Detail(
                                'Доходы',
                                _money(account.turnover.income, currency),
                              ),
                              _Detail(
                                'Расходы',
                                _money(account.turnover.expense, currency),
                              ),
                              if (account.active)
                                _Detail(
                                  'Остаток',
                                  _money(account.balance, account.currency),
                                ),
                            ],
                            note: account.active
                                ? null
                                : 'Архивный счёт не включён в общий баланс',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (report.ratesAsOf != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
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
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
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
                  SizedBox(
                    width: 125,
                    child: Text(
                      _money(value, report.currency),
                      textAlign: TextAlign.end,
                      maxLines: 2,
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

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.secondary,
  });
  final IconData icon;
  final String label, value, detail;
  final String? secondary;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(detail, style: theme.textTheme.bodySmall),
          if (secondary != null)
            Text(
              'Предыдущий период: $secondary',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _Detail {
  const _Detail(this.label, this.value);
  final String label, value;
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.note,
    this.margin = const EdgeInsets.only(bottom: 8),
  });
  final IconData icon;
  final String title;
  final List<_Detail> lines;
  final String? note;
  final EdgeInsets margin;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(line.label, style: theme.textTheme.bodySmall),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      line.value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(note!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}
