import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import '../accounts/accounts_repository.dart';
import '../accounts/money.dart';
import '../accounts/money_input_formatter.dart';
import 'transactions_repository.dart';

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String? _validateAmount(String? value) {
  final amount = Money.tryParse(value ?? '');
  if (amount == null ||
      amount.value.startsWith('-') ||
      RegExp(r'^0(?:\.0+)?$').hasMatch(amount.value)) {
    return 'Введите положительную сумму: до 18 цифр и 2 знаков после запятой';
  }
  return null;
}

class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm({super.key, this.transaction});
  final TransactionEntry? transaction;
  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount, _accountAmount, _description;
  late final AuthNavigation _navigation;
  late final String? _userId;
  late String _type, _date;
  String? _accountId, _categoryId, _currency;
  bool _saving = false, _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.transaction;
    _type = item?.type ?? 'expense';
    _date = item?.date ?? _isoDate(DateTime.now());
    _accountId = item?.accountId;
    _categoryId = item?.categoryId;
    _currency = item?.currency;
    _amount = TextEditingController(
      text: item == null ? '' : Money.displayStored(item.amount),
    );
    _accountAmount = TextEditingController(
      text: item == null ? '' : Money.displayStored(item.accountAmount),
    );
    _description = TextEditingController(text: item?.description ?? '');
    _navigation = ref.read(authNavigationProvider);
    _userId = _navigation.userId;
    _navigation.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_closing || (_navigation.hasSession && _navigation.userId == _userId)) {
      return;
    }
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    _navigation.removeListener(_onSessionChanged);
    _amount.dispose();
    _accountAmount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected != null && mounted) setState(() => _date = _isoDate(selected));
  }

  Future<void> _save(AccountSummary? account) async {
    if (!_form.currentState!.validate() ||
        account == null ||
        _categoryId == null ||
        _currency == null) {
      return;
    }
    if (!_navigation.hasSession ||
        _userId == null ||
        _navigation.userId != _userId) {
      setState(() => _error = 'Сессия изменилась. Откройте форму заново.');
      return;
    }
    final input = TransactionInput(
      accountId: account.id,
      categoryId: _categoryId!,
      type: _type,
      date: _date,
      amount: Money.tryParse(_amount.text)!.value,
      currency: _currency!,
      accountAmount: Money.tryParse(
        _currency == account.currency ? _amount.text : _accountAmount.text,
      )!.value,
      accountCurrency: account.currency,
      description: _description.text,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(transactionsRepositoryProvider);
      if (widget.transaction == null) {
        await repo.createTransaction(input);
      } else {
        await repo.updateTransaction(widget.transaction!.id, input);
      }
      if (!mounted) return;
      ref.invalidate(transactionsProvider);
      ref.invalidate(accountsProvider);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось сохранить операцию. Проверьте данные и подключение.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(transactionCategoriesProvider);
    final availableAccounts =
        accounts.asData?.value
            .where((a) => a.isActive || a.id == widget.transaction?.accountId)
            .toList() ??
        [];
    final account = availableAccounts
        .where((a) => a.id == _accountId)
        .firstOrNull;
    final availableCategories =
        categories.asData?.value.where((c) => c.kind == _type).toList() ?? [];
    final selectedCategory = availableCategories.any((c) => c.id == _categoryId)
        ? _categoryId
        : null;
    return AlertDialog(
      title: Text(
        widget.transaction == null
            ? 'Новая операция'
            : 'Редактировать операцию',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Тип операции'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Расход')),
                    DropdownMenuItem(value: 'income', child: Text('Доход')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _type = v!;
                          _categoryId = null;
                        }),
                ),
                accounts.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, s) => TextButton(
                    onPressed: () => ref.invalidate(accountsProvider),
                    child: const Text('Не удалось загрузить счета. Повторить'),
                  ),
                  data: (_) => DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: account?.id,
                    decoration: const InputDecoration(labelText: 'Счёт'),
                    items: [
                      for (final a in availableAccounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            '${a.name} · ${a.currency}${a.isActive ? '' : ' · архив'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (v) => v == null ? 'Выберите счёт' : null,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                            final old = account;
                            final next = availableAccounts.firstWhere(
                              (a) => a.id == v,
                            );
                            _accountId = v;
                            if (_currency == null ||
                                _currency == old?.currency) {
                              _currency = next.currency;
                            }
                          }),
                  ),
                ),
                if (widget.transaction != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'При изменении категории выбор запомнится для такого же названия, если оно достаточно длинное. Управление — в настройках.',
                    ),
                  ),
                categories.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, s) => TextButton(
                    onPressed: () =>
                        ref.invalidate(transactionCategoriesProvider),
                    child: const Text(
                      'Не удалось загрузить категории. Повторить',
                    ),
                  ),
                  data: (_) => DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('category-$_type'),
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: [
                      for (final c in availableCategories)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (v) => v == null ? 'Выберите категорию' : null,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _categoryId = v),
                  ),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('currency-$_currency'),
                  initialValue: supportedCurrencies.contains(_currency)
                      ? _currency
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Валюта операции',
                  ),
                  items: [
                    for (final currency in supportedCurrencies)
                      DropdownMenuItem(value: currency, child: Text(currency)),
                  ],
                  validator: (v) => v == null ? 'Выберите валюту' : null,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _currency = v),
                ),
                TextFormField(
                  controller: _amount,
                  enabled: !_saving,
                  inputFormatters: [MoneyInputFormatter()],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Сумма операции',
                    helperText:
                        'Положительная сумма, до 2 знаков после запятой.',
                  ),
                  validator: _validateAmount,
                ),
                if (account != null &&
                    _currency != null &&
                    _currency != account.currency)
                  TextFormField(
                    controller: _accountAmount,
                    enabled: !_saving,
                    inputFormatters: [MoneyInputFormatter()],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Сумма по счёту (${account.currency})',
                      helperText:
                          'Введите фактическую сумму без пересчёта по курсу.',
                    ),
                    validator: _validateAmount,
                  ),
                TextFormField(
                  controller: _description,
                  enabled: !_saving,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Описание (необязательно)',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Дата: $_date'),
                  ),
                ),
                if (accounts.hasValue && availableAccounts.isEmpty)
                  const Text(
                    'Сначала добавьте активный счёт в разделе «Счета».',
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving || !accounts.hasValue || !categories.hasValue
              ? null
              : () => _save(account),
          child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
        ),
      ],
    );
  }
}
