import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import '../../shared/section_state.dart';
import '../accounts/accounts_repository.dart';
import '../accounts/money.dart';
import 'transaction_form.dart';
import 'pending_notifications_dialog.dart';
import '../transfers/transfers_dialog.dart';
import 'transactions_repository.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  String _type = '', _account = '', _category = '', _currency = '';
  DateTimeRange? _dates;
  final Set<String> _busy = {};
  late final AuthNavigation _navigation;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _navigation = ref.read(authNavigationProvider);
    _userId = _navigation.userId;
    _navigation.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_userId == _navigation.userId) return;
    _userId = _navigation.userId;
    _search.clear();
    setState(() {
      _type = '';
      _account = '';
      _category = '';
      _currency = '';
      _dates = null;
    });
  }

  @override
  void dispose() {
    _navigation.removeListener(_onSessionChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit([TransactionEntry? item]) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => TransactionForm(transaction: item),
    );
  }

  Future<void> _delete(TransactionEntry item) async {
    final owner = ref.read(authNavigationProvider).userId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить операцию?'),
        content: const Text(
          'Операция будет удалена, а остаток счёта пересчитан. Отменить удаление нельзя.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        owner == null ||
        ref.read(authNavigationProvider).userId != owner) {
      return;
    }
    setState(() => _busy.add(item.id));
    try {
      await ref.read(transactionsRepositoryProvider).deleteTransaction(item.id);
      if (mounted) {
        ref.invalidate(transactionsProvider);
        ref.invalidate(accountsProvider);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось удалить операцию. Повторите попытку.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  void _openNotifications() {
    final owner = _userId;
    if (owner == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => PendingNotificationsDialog(owner: owner),
    );
  }

  Future<void> _selectDates() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _dates,
    );
    if (mounted && result != null) setState(() => _dates = result);
  }

  String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _filter(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> onChanged,
  ) {
    final selected = choices.containsKey(value) ? value : '';
    final scheme = Theme.of(context).colorScheme;
    final options = <String, String>{'': 'Все', ...choices};
    final border = BorderRadius.circular(14);
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Material(
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: border,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: PopupMenuButton<String>(
              key: ValueKey('transaction-filter-$label'),
              tooltip: '',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 6),
              elevation: 3,
              color: scheme.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              constraints: const BoxConstraints(
                minWidth: 200,
                maxWidth: 300,
                maxHeight: 320,
              ),
              borderRadius: border,
              onSelected: (v) => setState(() => onChanged(v)),
              itemBuilder: (context) => [
                for (final entry in options.entries)
                  PopupMenuItem<String>(
                    value: entry.key,
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.key == selected)
                          Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                      ],
                    ),
                  ),
              ],
              child: Semantics(
                label: '$label: ${options[selected]}',
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            options[selected]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    final pending = ref.watch(pendingNotificationsProvider(_userId ?? ''));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Операции',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Все операции',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            pending.maybeWhen(
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : MediaQuery.sizeOf(context).width < 500
                  ? IconButton(
                      tooltip: 'Предварительные уведомления (${items.length})',
                      onPressed: _openNotifications,
                      icon: Badge(
                        label: Text('${items.length}'),
                        child: const Icon(Icons.notifications_none_outlined),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _openNotifications,
                      icon: const Icon(Icons.notifications_none_outlined),
                      label: Text('Уведомления (${items.length})'),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            if (MediaQuery.sizeOf(context).width < 500)
              IconButton(
                tooltip: 'Переводы',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const TransfersDialog(),
                ),
                icon: const Icon(Icons.swap_horiz),
              )
            else
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const TransfersDialog(),
                ),
                child: const Text('Переводы'),
              ),
            if (MediaQuery.sizeOf(context).width < 500)
              IconButton.filled(
                tooltip: 'Добавить операцию',
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
              )
            else
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Добавить операцию'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: transactions.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => SectionState(
              icon: Icons.cloud_off_outlined,
              title: 'Не удалось загрузить операции',
              message:
                  'Проверьте подключение к интернету и попробуйте ещё раз.',
              action: OutlinedButton(
                onPressed: () => ref.invalidate(transactionsProvider),
                child: const Text('Повторить'),
              ),
            ),
            data: (items) {
              final accounts = <String, String>{
                for (final t in items) t.accountId: t.accountName,
              };
              final categories = <String, String>{
                for (final t in items) t.categoryId: t.categoryName,
              };
              final currencies = <String, String>{
                for (final t in items) t.currency: t.currency,
              };
              final selectedAccount = accounts.containsKey(_account)
                  ? _account
                  : '';
              final selectedCategory = categories.containsKey(_category)
                  ? _category
                  : '';
              final selectedCurrency = currencies.containsKey(_currency)
                  ? _currency
                  : '';
              final query = _search.text.trim().toLowerCase();
              final filtered = items
                  .where(
                    (t) =>
                        (_type.isEmpty ||
                            (_type == 'transfer'
                                ? t.transferGroupId != null
                                : t.transferGroupId == null &&
                                      t.type == _type)) &&
                        (selectedAccount.isEmpty ||
                            t.accountId == selectedAccount) &&
                        (selectedCategory.isEmpty ||
                            t.categoryId == selectedCategory) &&
                        (selectedCurrency.isEmpty ||
                            t.currency == selectedCurrency) &&
                        (_dates == null ||
                            (t.date.compareTo(_day(_dates!.start)) >= 0 &&
                                t.date.compareTo(_day(_dates!.end)) <= 0)) &&
                        (query.isEmpty ||
                            '${t.description ?? ''} ${t.accountName} ${t.categoryName}'
                                .toLowerCase()
                                .contains(query)),
                  )
                  .toList();
              return ListView(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Поиск по операциям, счетам и категориям',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: [
                      _filter('Тип', _type, {
                        'income': 'Доход',
                        'expense': 'Расход',
                        'transfer': 'Перевод',
                      }, (v) => _type = v),
                      _filter('Счёт', _account, accounts, (v) => _account = v),
                      _filter(
                        'Категория',
                        _category,
                        categories,
                        (v) => _category = v,
                      ),
                      _filter(
                        'Валюта',
                        _currency,
                        currencies,
                        (v) => _currency = v,
                      ),
                      TextButton.icon(
                        onPressed: _selectDates,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _dates == null
                              ? 'Период'
                              : '${_day(_dates!.start)} — ${_day(_dates!.end)}',
                        ),
                      ),
                      if (_dates != null)
                        TextButton(
                          onPressed: () => setState(() => _dates = null),
                          child: const Text('Сбросить период'),
                        ),
                      TextButton(
                        onPressed: () => setState(() {
                          _type = '';
                          _account = '';
                          _category = '';
                          _currency = '';
                          _dates = null;
                          _search.clear();
                        }),
                        child: const Text('Сбросить фильтры'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (filtered.isNotEmpty) ...[
                    Text(
                      'История операций',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: SectionState(
                        icon: Icons.receipt_long_outlined,
                        title: items.isEmpty
                            ? 'История операций'
                            : 'Операции не найдены',
                        message: items.isEmpty
                            ? 'Добавьте первый доход или расход.'
                            : 'Измените параметры фильтра.',
                      ),
                    ),
                  for (final item in filtered) _card(item),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _card(TransactionEntry item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amount = Money.displayStored(item.amount);
    final accountAmount = Money.displayStored(item.accountAmount);
    final sign = item.type == 'income' ? '+' : '−';
    final transfer = item.transferGroupId != null;
    final canEdit =
        !_busy.contains(item.id) &&
        !transfer &&
        item.transferFeeGroupId == null;
    final description = item.description?.isNotEmpty == true
        ? item.description!
        : transfer
        ? 'Внутренний перевод'
        : item.type == 'income'
        ? 'Доход'
        : 'Расход';
    final amountWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$sign$amount ${item.currency}',
          textAlign: TextAlign.end,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (item.currency != item.accountCurrency)
          Text(
            'По счёту: $sign$accountAmount ${item.accountCurrency}',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '${item.date} · ${item.accountName}${item.accountActive ? '' : ' · архив'} · ${item.categoryName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (item.postingDate != null)
                  Text(
                    'Дата проводки: ${item.postingDate} · код: ${item.bankOperationCode ?? '—'}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (!item.originalAmountKnown)
                  Text(
                    'Сумма по счёту; сумма и валюта покупки в выписке не указаны.',
                    style: theme.textTheme.bodySmall,
                  ),
                if (transfer)
                  Text(
                    'Внутренний перевод · не доход и не расход',
                    style: theme.textTheme.bodySmall,
                  ),
                if (item.transferFeeGroupId != null)
                  Text(
                    'Комиссия перевода · расход',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        transfer
                            ? Icons.swap_horiz_rounded
                            : item.type == 'income'
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: details),
                    if (wide) ...[
                      const SizedBox(width: 20),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .38,
                        ),
                        child: amountWidget,
                      ),
                    ],
                  ],
                ),
                if (!wide) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: amountWidget),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: canEdit ? () => _edit(item) : null,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Изменить'),
                    ),
                    TextButton.icon(
                      onPressed: canEdit ? () => _delete(item) : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Удалить'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
