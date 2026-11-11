import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import '../../shared/section_state.dart';
import '../accounts/accounts_repository.dart';
import '../accounts/money.dart';
import 'transaction_form.dart';
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
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$selected-${choices.keys.join(",")}'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Все')),
          for (final entry in choices.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => onChanged(v ?? '')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
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
                  'Доходы и расходы',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Добавить операцию'),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                        (_type.isEmpty || t.type == _type) &&
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
                    decoration: const InputDecoration(
                      labelText: 'Поиск',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _filter('Тип', _type, {
                        'income': 'Доход',
                        'expense': 'Расход',
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
                  const SizedBox(height: 20),
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
    final amount = Money.displayStored(item.amount);
    final accountAmount = Money.displayStored(item.accountAmount);
    final sign = item.type == 'income' ? '+' : '−';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.description?.isNotEmpty == true
                  ? item.description!
                  : (item.type == 'income' ? 'Доход' : 'Расход'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${item.date} · ${item.accountName}${item.accountActive ? '' : ' · архив'} · ${item.categoryName}',
            ),
            const SizedBox(height: 8),
            Text(
              '$sign$amount ${item.currency}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (item.currency != item.accountCurrency)
              Text('По счёту: $sign$accountAmount ${item.accountCurrency}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy.contains(item.id) ? null : () => _edit(item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Изменить'),
                ),
                TextButton.icon(
                  onPressed: _busy.contains(item.id)
                      ? null
                      : () => _delete(item),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
