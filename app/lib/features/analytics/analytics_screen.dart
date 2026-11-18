import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/auth_navigation.dart';
import '../accounts/money.dart';
import '../accounts/money_input_formatter.dart';
import '../settings/currency_repository.dart';
import '../transactions/transactions_repository.dart';
import 'analytics_repository.dart';
import 'analytics_format.dart';
import '../../app/theme_preference.dart';
import 'period_analytics.dart';

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
  Color(0xffffd500),
  Color(0xff242424),
  Color(0xffffa940),
  Color(0xff8d7bea),
  Color(0xff80b89a),
  Color(0xffef8585),
  Color(0xff799bd0),
  Color(0xffc5a45b),
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
    final dark = ref.watch(appDarkModeProvider);
    final foreground = dark ? const Color(0xfff5f5f1) : const Color(0xff20201e);
    final scheme = theme.colorScheme.copyWith(
      primary: dark ? const Color(0xffffd500) : const Color(0xff222222),
      onPrimary: dark ? const Color(0xff191919) : Colors.white,
      primaryContainer: const Color(0xffffd500),
      onPrimaryContainer: const Color(0xff191919),
      secondaryContainer: const Color(0xffffd500),
      onSecondaryContainer: const Color(0xff191919),
      surface: dark ? const Color(0xff252525) : Colors.white,
      surfaceContainerLow: dark
          ? const Color(0xff30302e)
          : const Color(0xfff5f5f2),
      outline: dark ? const Color(0xff777770) : const Color(0xffb8b8b0),
      outlineVariant: dark ? const Color(0xff454540) : const Color(0xffe9e9e4),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        textTheme: theme.textTheme
            .apply(bodyColor: foreground, displayColor: foreground)
            .copyWith(
              titleLarge: theme.textTheme.titleLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
              ),
              titleMedium: theme.textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
              headlineSmall: theme.textTheme.headlineSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
              bodySmall: theme.textTheme.bodySmall?.copyWith(
                color: dark ? const Color(0xffb8b8b0) : const Color(0xff777770),
              ),
            ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffffd500),
            foregroundColor: const Color(0xff191919),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: scheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            side: WidgetStatePropertyAll(
              BorderSide(color: scheme.outlineVariant),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: const Color(0xffffd500),
          linearTrackColor: dark
              ? const Color(0xff3a3a37)
              : const Color(0xfff0f0eb),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Аналитика',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              currencyValue.when(
                data: (currency) => DropdownButton<String>(
                  value: supportedCurrencies.contains(currency)
                      ? currency
                      : null,
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
                data: (currency) => MediaQuery.sizeOf(context).width < 560
                    ? IconButton.filled(
                        tooltip: 'Установить бюджет',
                        onPressed: () => _budget(currency),
                        icon: const Icon(Icons.add),
                      )
                    : FilledButton.icon(
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
      ),
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
    final chartRows = rows.where((r) => r.spent > BigInt.zero).toList();
    final overview = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _expense ? 'Расходы по категориям' : 'Доходы по категориям',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${_months[_month.month - 1]} ${_month.year}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (chartRows.isNotEmpty)
                      SizedBox(
                        width: 176,
                        height: 176,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(176, 176),
                              painter: _DonutPainter(
                                chartRows,
                                theme.brightness == Brightness.dark,
                              ),
                            ),
                            Text(
                              _months[_month.month - 1],
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Icon(
                          Icons.pie_chart_outline,
                          size: 52,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '${analyticsAmount(total)} $currency',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      _expense ? 'Расходы за месяц' : 'Доходы за месяц',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_expense && budgeted.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'С лимитом: ${analyticsAmount(limitedSpent)} из ${analyticsAmount(limit)} $currency',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (limitedSpent > limit)
                        Text(
                          'Превышение: ${analyticsAmount(limitedSpent - limit)} $currency',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                    ],
                  ],
                );
                final categories = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Добавьте бюджет или операции, чтобы увидеть категории.',
                        ),
                      ),
                    for (var i = 0; i < rows.length; i++)
                      _category(
                        rows[i],
                        currency,
                        _chartColor(i, theme.brightness == Brightness.dark),
                      ),
                  ],
                );
                if (constraints.maxWidth >= 720) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 260, child: summary),
                      const SizedBox(width: 24),
                      Expanded(child: categories),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 16), categories],
                );
              },
            ),
            if (data.ratesAsOf != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Приблизительный пересчёт по текущему безналичному курсу покупки ACBA / Rate.am на ${data.ratesAsOf!.toLocal().toString().substring(0, 16)}. Для прошлых месяцев курс не исторический.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
    return ListView(
      children: [
        if (_owner != null)
          PeriodAnalytics(
            owner: _owner!,
            currency: currency,
            month: _month,
            monthlyOverview: overview,
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
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
                        child: Text(
                          row.name,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${analyticsAmount(row.spent)} $currency',
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
                    '${row.count} оп. ${limit == null ? '' : '· лимит ${analyticsAmount(limit)} $currency'}',
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
                          ? 'Превышение ${analyticsAmount(row.spent - limit)} $currency'
                          : 'Осталось ${analyticsAmount(limit - row.spent)} $currency',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (_expense)
              IconButton(
                tooltip: limit == null
                    ? 'Установить бюджет'
                    : 'Изменить бюджет',
                onPressed: () => _budget(currency, row),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
      ),
    );
  }
}

Color _chartColor(int index, bool dark) => dark && index % _colors.length == 1
    ? const Color(0xffe4e4dc)
    : _colors[index % _colors.length];

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.rows, this.dark);
  final List<AnalyticsRow> rows;
  final bool dark;
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
          ..color = _chartColor(i, dark)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.rows != rows || oldDelegate.dark != dark;
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
