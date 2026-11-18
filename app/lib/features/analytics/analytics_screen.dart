import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/auth_navigation.dart';
import '../accounts/money.dart';
import '../accounts/money_input_formatter.dart';
import '../settings/currency_repository.dart';
import '../transactions/transactions_repository.dart';
import 'analytics_repository.dart';

const _months = [
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];
const _colors = [
  Color(0xff008b82),
  Color(0xff6099db),
  Color(0xffe39843),
  Color(0xffa069ce),
  Color(0xff83a94e),
  Color(0xffd26b76),
  Color(0xff5972b7),
  Color(0xffc89b3f),
];
String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-01';

IconData _categoryIcon(AnalyticsRow row) {
  final name = row.name.toLowerCase();
  if (name.contains('продукт')) return Icons.shopping_basket_outlined;
  if (name.contains('ресторан') || name.contains('кафе')) {
    return Icons.restaurant_outlined;
  }
  if (name.contains('доставк')) return Icons.delivery_dining_outlined;
  if (name.contains('транспорт') || name.contains('такси')) {
    return Icons.directions_car_outlined;
  }
  if (name.contains('здоров') || name.contains('аптек')) {
    return Icons.medical_services_outlined;
  }
  if (name.contains('связ') || name.contains('интернет')) {
    return Icons.wifi_outlined;
  }
  if (name.contains('развлечен')) return Icons.movie_outlined;
  if (row.type == 'income') return Icons.account_balance_wallet_outlined;
  return Icons.category_outlined;
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late final AuthNavigation _auth;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _expense = true;
  String? _owner;
  @override
  void initState() {
    super.initState();
    _auth = ref.read(authNavigationProvider);
    _owner = _auth.userId;
    _auth.addListener(_identityChanged);
  }

  void _identityChanged() {
    if (_owner == _auth.userId) return;
    setState(() {
      _owner = _auth.userId;
      _month = DateTime(DateTime.now().year, DateTime.now().month);
      _expense = true;
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_identityChanged);
    super.dispose();
  }

  Future<void> _budget(String currency, [AnalyticsRow? row]) async {
    final owner = _owner;
    if (owner == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => BudgetDialog(
        owner: owner,
        month: _monthKey(_month),
        currency: currency,
        row: row,
      ),
    );
    if (mounted && changed == true && owner == _owner) {
      ref.invalidate(
        monthlyAnalyticsProvider((owner, _monthKey(_month), currency)),
      );
    }
  }

  Future<void> _changeCurrency(String value) async {
    final owner = _owner;
    try {
      await ref.read(currencyRepositoryProvider).saveBaseCurrency(value);
      if (mounted && owner == _owner) ref.invalidate(baseCurrencyProvider);
    } catch (_) {
      if (mounted && owner == _owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось изменить валюту.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        currencyValue = ref.watch(baseCurrencyProvider);
    final owner = _owner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Аналитика', style: theme.textTheme.headlineMedium),
            currencyValue.when(
              data: (currency) => DropdownButton<String>(
                value: supportedCurrencies.contains(currency) ? currency : null,
                hint: const Text('Валюта'),
                items: [
                  for (final code in supportedCurrencies)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: (v) {
                  if (v != null && v != currency) _changeCurrency(v);
                },
              ),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(baseCurrencyProvider),
                child: const Text('Повторить загрузку валюты'),
              ),
              loading: () => const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            currencyValue.maybeWhen(
              data: (currency) => FilledButton.icon(
                onPressed: () => _budget(currency),
                icon: const Icon(Icons.add),
                label: const Text('Установить бюджет'),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Предыдущий месяц',
              onPressed: _month.year > 1900 || _month.month > 1
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${_months[_month.month - 1]} ${_month.year}',
              style: theme.textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Следующий месяц',
              onPressed: _month.year < 2100 || _month.month < 12
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Расходы')),
                ButtonSegment(value: false, label: Text('Доходы')),
              ],
              selected: {_expense},
              onSelectionChanged: (value) =>
                  setState(() => _expense = value.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: currencyValue.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Не удалось загрузить валюту.')),
            data: (currency) {
              if (owner == null) return const SizedBox.shrink();
              final key = (owner, _monthKey(_month), currency);
              return ref
                  .watch(monthlyAnalyticsProvider(key))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Не удалось загрузить аналитику или курсы валют.',
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(monthlyAnalyticsProvider(key)),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                    data: (data) => _content(data, currency),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _content(MonthlyAnalytics data, String currency) {
    final theme = Theme.of(context);
    final rows = data.rows
        .where((row) => row.type == (_expense ? 'expense' : 'income'))
        .toList();
    final total = rows.fold(BigInt.zero, (sum, row) => sum + row.spent);
    final budgeted = rows.where((r) => r.limit != null).toList();
    final limit = budgeted.fold(BigInt.zero, (sum, row) => sum + row.limit!);
    final limitedSpent = budgeted.fold(
      BigInt.zero,
      (sum, row) => sum + row.spent,
    );
    final usedForChart = rows.where((r) => r.spent > BigInt.zero).toList();
    return ListView(
      children: [
        if (usedForChart.isNotEmpty)
          SizedBox(
            height: 200,
            child: Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(180, 180),
                      painter: _DonutPainter(usedForChart),
                    ),
                    Text(
                      _months[_month.month - 1],
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (usedForChart.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: Text(
                'За этот месяц операций нет',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          '${ExchangeRates.display(total)} $currency',
          style: theme.textTheme.headlineMedium,
        ),
        Text(
          _expense ? 'Расходы за месяц' : 'Доходы за месяц',
          style: theme.textTheme.bodyMedium,
        ),
        if (_expense && budgeted.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'По категориям с лимитом: ${ExchangeRates.display(limitedSpent)} из ${ExchangeRates.display(limit)} $currency',
          ),
          if (limitedSpent > limit)
            Text(
              'Превышение: ${ExchangeRates.display(limitedSpent - limit)} $currency',
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
        if (data.ratesAsOf != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Приблизительный пересчёт по текущему безналичному курсу покупки ACBA / Rate.am на ${data.ratesAsOf!.toLocal().toString().substring(0, 16)}. Для прошлых месяцев курс не исторический.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 24),
        Text('Категории', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Добавьте бюджет или операции, чтобы увидеть категории.',
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          _category(rows[i], currency, _colors[i % _colors.length]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _category(AnalyticsRow row, String currency, Color color) {
    final theme = Theme.of(context), limit = row.limit;
    final ratio = limit == null || limit == BigInt.zero
        ? 0.0
        : (row.spent.toDouble() / limit.toDouble()).clamp(0.0, 1.0);
    final exceeded = limit != null && row.spent > limit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_categoryIcon(row), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(row.name, style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${ExchangeRates.display(row.spent)} $currency',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: exceeded ? theme.colorScheme.error : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${row.count} оп. ${limit == null ? '' : '· лимит ${ExchangeRates.display(limit)} $currency'}',
                  style: theme.textTheme.bodySmall,
                ),
                if (limit != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ratio,
                    color: exceeded ? theme.colorScheme.error : color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exceeded
                        ? 'Превышение ${ExchangeRates.display(row.spent - limit)} $currency'
                        : 'Осталось ${ExchangeRates.display(limit - row.spent)} $currency',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (_expense)
            IconButton(
              tooltip: limit == null ? 'Установить бюджет' : 'Изменить бюджет',
              onPressed: () => _budget(currency, row),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.rows);
  final List<AnalyticsRow> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final total = rows
        .fold(BigInt.zero, (sum, row) => sum + row.spent)
        .toDouble();
    if (total <= 0) return;
    var start = -math.pi / 2;
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    for (var i = 0; i < rows.length; i++) {
      final sweep = rows[i].spent.toDouble() / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = _colors[i % _colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.rows != rows;
}

class BudgetDialog extends ConsumerStatefulWidget {
  const BudgetDialog({
    required this.owner,
    required this.month,
    required this.currency,
    this.row,
    super.key,
  });
  final String owner, month, currency;
  final AnalyticsRow? row;
  @override
  ConsumerState<BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends ConsumerState<BudgetDialog> {
  final _form = GlobalKey<FormState>();
  late final AuthNavigation _auth;
  late final TextEditingController _amount;
  late String _currency;
  String? _category;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _auth = ref.read(authNavigationProvider);
    _auth.addListener(_checkSession);
    _currency = widget.row?.limitCurrency ?? widget.currency;
    _category = widget.row?.categoryId;
    _amount = TextEditingController(
      text: widget.row?.limitOriginal == null
          ? ''
          : Money.displayStored(widget.row!.limitOriginal!),
    );
  }

  void _checkSession() {
    if (_auth.userId == widget.owner && _auth.hasSession) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_checkSession);
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save({bool stop = false}) async {
    if (!stop && !_form.currentState!.validate()) return;
    if (_category == null ||
        _auth.userId != widget.owner ||
        !_auth.hasSession) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(analyticsRepositoryProvider)
          .saveBudget(
            _category!,
            widget.month,
            _currency,
            stop ? null : Money.tryParse(_amount.text)!.value,
          );
      if (mounted && _auth.userId == widget.owner) Navigator.pop(context, true);
    } catch (_) {
      if (mounted && _auth.userId == widget.owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить бюджет.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(transactionCategoriesProvider);
    return AlertDialog(
      title: Text(
        widget.row?.limit == null ? 'Установить бюджет' : 'Изменить бюджет',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Лимит действует с выбранного месяца и повторяется до изменения.',
                ),
                const SizedBox(height: 16),
                cats.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => TextButton(
                    onPressed: () =>
                        ref.invalidate(transactionCategoriesProvider),
                    child: const Text(
                      'Не удалось загрузить категории. Повторить',
                    ),
                  ),
                  data: (items) {
                    final options = items
                        .where((e) => e.kind == 'expense')
                        .toList();
                    return DropdownButtonFormField<String>(
                      initialValue: options.any((e) => e.id == _category)
                          ? _category
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Категория'),
                      items: [
                        for (final c in options)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: widget.row == null && !_saving
                          ? (v) => setState(() => _category = v)
                          : null,
                      validator: (v) => v == null ? 'Выберите категорию' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Валюта лимита'),
                  items: [
                    for (final code in supportedCurrencies)
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v != null) setState(() => _currency = v);
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Лимит на месяц',
                  ),
                  validator: (v) {
                    final value = Money.tryParse(v ?? '');
                    if (value == null ||
                        value.value.startsWith('-') ||
                        RegExp(r'^0(?:\.0+)?$').hasMatch(value.value)) {
                      return 'Введите положительную сумму';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.row?.limit != null)
          TextButton(
            onPressed: _saving ? null : () => _save(stop: true),
            child: const Text('Отключить лимит'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _save(),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
