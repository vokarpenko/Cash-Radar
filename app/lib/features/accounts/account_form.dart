import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import 'accounts_repository.dart';
import 'money.dart';

class AccountForm extends ConsumerStatefulWidget {
  const AccountForm({super.key, this.account});
  final AccountSummary? account;
  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late final String? _userId;
  late final AuthNavigation _navigation;
  late String _type;
  late String _currency;
  String? _bankId;
  bool _saving = false;
  bool _closingForSessionChange = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _name = TextEditingController(text: a?.name ?? '');
    _balance = TextEditingController(
      text: a == null ? '0' : Money.displayStored(a.initialBalance),
    );
    _type = a?.type ?? 'bank';
    _currency = a?.currency ?? 'AMD';
    _bankId = a?.bankId;
    _navigation = ref.read(authNavigationProvider);
    _userId = _navigation.userId;
    _navigation.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_closingForSessionChange ||
        (_navigation.hasSession && _navigation.userId == _userId)) {
      return;
    }
    _closingForSessionChange = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    _navigation.removeListener(_onSessionChanged);
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final nav = ref.read(authNavigationProvider);
    if (!nav.hasSession || _userId == null || nav.userId != _userId) {
      setState(() => _error = 'Сессия изменилась. Откройте форму заново.');
      return;
    }
    final amount = Money.tryParse(_balance.text)!;
    final input = AccountInput(
      name: _name.text,
      type: _type,
      currency: _currency,
      initialBalance: amount.value,
      bankId: _bankId,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(accountsRepositoryProvider);
      if (widget.account == null) {
        await repo.createAccount(input);
      } else {
        await repo.updateAccount(widget.account!.id, input);
      }
      if (!mounted) return;
      ref.invalidate(accountsProvider);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось сохранить счёт. Проверьте подключение и повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = _type == 'bank' ? ref.watch(banksProvider) : null;
    return AlertDialog(
      title: Text(widget.account == null ? 'Новый счёт' : 'Редактировать счёт'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Название'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Введите название' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Тип'),
                  items: const [
                    DropdownMenuItem(
                      value: 'bank',
                      child: Text('Банковский счёт'),
                    ),
                    DropdownMenuItem(value: 'cash', child: Text('Наличные')),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text('Другой кошелёк'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _type = v!;
                          if (_type != 'bank') _bankId = null;
                        }),
                ),
                if (banks != null)
                  banks.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, stack) => TextButton(
                      onPressed: _saving
                          ? null
                          : () => ref.invalidate(banksProvider),
                      child: const Text(
                        'Не удалось загрузить банки. Повторить',
                      ),
                    ),
                    data: (items) => DropdownButtonFormField<String>(
                      initialValue: items.any((b) => b.id == _bankId)
                          ? _bankId
                          : null,
                      decoration: const InputDecoration(labelText: 'Банк'),
                      items: [
                        for (final bank in items)
                          DropdownMenuItem(
                            value: bank.id,
                            child: Text(bank.name),
                          ),
                      ],
                      validator: (v) => v == null ? 'Выберите банк' : null,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _bankId = v),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: supportedCurrencies.contains(_currency)
                      ? _currency
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Валюта',
                    helperText: widget.account?.hasTransactions == true
                        ? 'Нельзя менять валюту счёта с операциями.'
                        : null,
                  ),
                  items: [
                    for (final currency in supportedCurrencies)
                      DropdownMenuItem(value: currency, child: Text(currency)),
                  ],
                  validator: (v) => v == null ? 'Выберите валюту' : null,
                  onChanged: _saving || widget.account?.hasTransactions == true
                      ? null
                      : (v) => setState(() => _currency = v!),
                ),
                TextFormField(
                  controller: _balance,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(25)],
                  decoration: const InputDecoration(
                    labelText: 'Начальный баланс',
                    helperText:
                        'До 2 знаков после запятой; можно указать минус.',
                  ),
                  validator: (v) => Money.tryParse(v ?? '') == null
                      ? 'Введите сумму до 18 цифр и 2 знаков после запятой'
                      : null,
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
          onPressed: _saving || (banks != null && !banks.hasValue)
              ? null
              : _save,
          child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
        ),
      ],
    );
  }
}
