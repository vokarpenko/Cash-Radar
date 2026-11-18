import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import '../accounts/accounts_repository.dart';
import '../accounts/money.dart';
import '../accounts/money_input_formatter.dart';
import '../transactions/transactions_repository.dart';
import 'transfers_repository.dart';

class TransfersDialog extends ConsumerStatefulWidget {
  const TransfersDialog({super.key});
  @override
  ConsumerState<TransfersDialog> createState() => _TransfersDialogState();
}

class _TransfersDialogState extends ConsumerState<TransfersDialog> {
  late final AuthNavigation _nav;
  late final String? _owner;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _nav = ref.read(authNavigationProvider);
    _owner = _nav.userId;
    _nav.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_nav.hasSession && _nav.userId == _owner) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route is PageRoute);
      }
    });
  }

  @override
  void dispose() {
    _nav.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _run(Future<void> Function(TransfersRepository) action) async {
    if (_busy || _owner == null || _nav.userId != _owner) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(transfersRepositoryProvider));
      if (!mounted || _nav.userId != _owner) return;
      ref.invalidate(transferCandidatesProvider);
      ref.invalidate(transferGroupsProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(accountsProvider);
    } catch (_) {
      if (mounted && _nav.userId == _owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить перевод. Проверьте операции и повторите.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _approve(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      ) ??
      false;
  String _pair(Map<String, dynamic> r) =>
      '${r['debit_account']}: ${Money.displayStored(r['debit_amount'] as String)} ${r['debit_currency']} → ${r['credit_account']}: ${Money.displayStored(r['credit_amount'] as String)} ${r['credit_currency']}';
  Future<void> _openForm(Widget child) async {
    if (_busy || _nav.userId != _owner) return;
    await showDialog<void>(context: context, builder: (_) => child);
    if (!mounted || _nav.userId != _owner) return;
    ref.invalidate(transferCandidatesProvider);
    ref.invalidate(transferGroupsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(accountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(transferCandidatesProvider),
        groups = ref.watch(transferGroupsProvider);
    return AlertDialog(
      title: const Text('Внутренние переводы'),
      content: SizedBox(
        width: 760,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Перевод меняет остатки счетов, но не считается доходом или расходом. Комиссия остаётся расходом.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () => _openForm(const ManualTransferForm()),
                  child: const Text('Новый перевод'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _openForm(const LinkTransferForm()),
                  child: const Text('Связать операции вручную'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _openForm(const CashTransferForm()),
                  child: const Text('Снятие наличных'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Возможные переводы',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Проверьте обе операции. Разные валюты и суммы не подтверждают перевод сами по себе.',
            ),
            candidates.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(transferCandidatesProvider),
                child: const Text(
                  'Не удалось загрузить предложения. Повторить',
                ),
              ),
              data: (items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isEmpty) const Text('Предложений пока нет.'),
                  for (final c in items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_pair(c)),
                            Text(
                              '${c['debit_date']} → ${c['credit_date']} · ${c['exact_amount'] == true ? 'одинаковая сумма и валюта' : 'разные валюты — проверьте суммы'}',
                            ),
                            if (c['debit_description'] != null)
                              Text('Списание: ${c['debit_description']}'),
                            if (c['credit_description'] != null)
                              Text('Поступление: ${c['credit_description']}'),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          if (await _approve(
                                            'Подтвердить перевод?',
                                            '${_pair(c)}\n\nОбе операции будут исключены из доходов и расходов.',
                                          )) {
                                            await _run(
                                              (r) => r.confirm(
                                                c['debit_id'] as String,
                                                c['credit_id'] as String,
                                                debitVersion:
                                                    c['debit_updated_at']
                                                        as String?,
                                                creditVersion:
                                                    c['credit_updated_at']
                                                        as String?,
                                              ),
                                            );
                                          }
                                        },
                                  child: const Text('Это перевод'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          (r) => r.reject(
                                            c['debit_id'] as String,
                                            c['credit_id'] as String,
                                          ),
                                        ),
                                  child: const Text('Не перевод'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (items.length >= 300)
                    const Text('Показаны первые 300 предложений.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Подтверждённые переводы',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            groups.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(transferGroupsProvider),
                child: const Text('Не удалось загрузить переводы. Повторить'),
              ),
              data: (items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isEmpty) const Text('Переводов пока нет.'),
                  for (final g in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_pair(g)),
                      subtitle: Text(
                        '${g['debit_date']} → ${g['credit_date']}${g['fee_amount'] == null ? '' : ' · комиссия ${Money.displayStored(g['fee_amount'] as String)} ${g['fee_currency']}'}',
                      ),
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _approve(
                                  'Разъединить перевод?',
                                  'Операции и остатки сохранятся, но списание и поступление снова будут считаться расходом и доходом.',
                                )) {
                                  await _run(
                                    (r) => r.unlink(g['id'] as String),
                                  );
                                }
                              },
                        child: const Text('Разъединить'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String? _moneyValidation(String? value, {bool allowZero = false}) {
  final parsed = Money.tryParse(value ?? '');
  if (parsed == null ||
      parsed.value.startsWith('-') ||
      (!allowZero && RegExp(r'^0(?:\.0+)?$').hasMatch(parsed.value))) {
    return 'Введите сумму до 2 знаков после запятой';
  }
  return null;
}

String _newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ManualTransferForm extends ConsumerStatefulWidget {
  const ManualTransferForm({super.key});
  @override
  ConsumerState<ManualTransferForm> createState() => _ManualTransferFormState();
}

class _ManualTransferFormState extends ConsumerState<ManualTransferForm> {
  final _requestId = _newRequestId();
  final _form = GlobalKey<FormState>();
  final _fromAmount = TextEditingController(),
      _toAmount = TextEditingController(),
      _fee = TextEditingController(text: '0'),
      _description = TextEditingController();
  String? _from, _to;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(authNavigationProvider).userId;
  }

  @override
  void dispose() {
    _fromAmount.dispose();
    _toAmount.dispose();
    _fee.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref
            .watch(accountsProvider)
            .asData
            ?.value
            .where((x) => x.isActive)
            .toList() ??
        <AccountSummary>[];
    final a = accounts.where((x) => x.id == _from).firstOrNull,
        b = accounts.where((x) => x.id == _to).firstOrNull;
    final same = a != null && b != null && a.currency == b.currency;
    return AlertDialog(
      title: const Text('Новый перевод'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  menuMaxHeight: 320,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  initialValue: _from,
                  decoration: const InputDecoration(labelText: 'Со счёта'),
                  items: [
                    for (final x in accounts)
                      DropdownMenuItem(
                        value: x.id,
                        child: Text('${x.name} · ${x.currency}'),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _from = v),
                  validator: (v) => v == null ? 'Выберите счёт' : null,
                ),
                DropdownButtonFormField<String>(
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  menuMaxHeight: 320,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  initialValue: _to,
                  decoration: const InputDecoration(labelText: 'На счёт'),
                  items: [
                    for (final x in accounts)
                      DropdownMenuItem(
                        value: x.id,
                        child: Text('${x.name} · ${x.currency}'),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _to = v),
                  validator: (v) =>
                      v == null || v == _from ? 'Выберите другой счёт' : null,
                ),
                TextFormField(
                  controller: _fromAmount,
                  inputFormatters: [MoneyInputFormatter()],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Списано ${a?.currency ?? ''}',
                  ),
                  validator: (v) => _moneyValidation(v),
                ),
                if (!same)
                  TextFormField(
                    controller: _toAmount,
                    inputFormatters: [MoneyInputFormatter()],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Зачислено ${b?.currency ?? ''}',
                    ),
                    validator: (v) => _moneyValidation(v),
                  ),
                TextFormField(
                  controller: _fee,
                  inputFormatters: [MoneyInputFormatter()],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Комиссия ${a?.currency ?? ''}',
                  ),
                  validator: (v) => _moneyValidation(v, allowZero: true),
                ),
                TextFormField(
                  controller: _description,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Описание (необязательно)',
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100, 12, 31),
                          );
                          if (d != null && mounted) setState(() => _date = d);
                        },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_dateString(_date)),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  if (!_form.currentState!.validate() ||
                      a == null ||
                      b == null ||
                      _owner == null ||
                      ref.read(authNavigationProvider).userId != _owner) {
                    return;
                  }
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    await ref
                        .read(transfersRepositoryProvider)
                        .create(
                          from: a.id,
                          to: b.id,
                          date: _dateString(_date),
                          fromAmount: Money.tryParse(_fromAmount.text)!.value,
                          toAmount: same
                              ? Money.tryParse(_fromAmount.text)!.value
                              : Money.tryParse(_toAmount.text)!.value,
                          fee: Money.tryParse(_fee.text)!.value,
                          requestId: _requestId,
                          description: _description.text,
                        );
                    if (context.mounted &&
                        mounted &&
                        ref.read(authNavigationProvider).userId == _owner) {
                      Navigator.pop(context);
                    }
                  } catch (_) {
                    if (mounted &&
                        ref.read(authNavigationProvider).userId == _owner) {
                      setState(
                        () => _error =
                            'Не удалось создать перевод. Проверьте счета и суммы.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_busy ? 'Сохранение…' : 'Создать перевод'),
        ),
      ],
    );
  }
}

class LinkTransferForm extends ConsumerStatefulWidget {
  const LinkTransferForm({super.key});
  @override
  ConsumerState<LinkTransferForm> createState() => _LinkTransferFormState();
}

class _LinkTransferFormState extends ConsumerState<LinkTransferForm> {
  String? _debit, _credit, _fee;
  bool _busy = false;
  String? _error;
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(authNavigationProvider).userId;
  }

  String _title(TransactionEntry t) =>
      '${t.date} · ${t.accountName} · ${Money.displayStored(t.accountAmount)} ${t.accountCurrency}';
  @override
  Widget build(BuildContext context) {
    final items =
        ref
            .watch(transactionsProvider)
            .asData
            ?.value
            .where(
              (t) => t.transferGroupId == null && t.transferFeeGroupId == null,
            )
            .toList() ??
        <TransactionEntry>[];
    final debits = items.where((t) => t.type == 'expense').toList(),
        credits = items.where((t) => t.type == 'income').toList();
    final debit = debits.where((t) => t.id == _debit).firstOrNull,
        credit = credits.where((t) => t.id == _credit).firstOrNull;
    return AlertDialog(
      title: const Text('Связать операции'),
      content: SizedBox(
        width: 550,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Выберите списание и поступление с разных счетов. При конвертации проверьте фактические суммы вручную.',
            ),
            DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(16),
              dropdownColor: Theme.of(context).colorScheme.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              initialValue: _debit,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Списание'),
              items: [
                for (final t in debits)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(_title(t), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _debit = v),
            ),
            DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(16),
              dropdownColor: Theme.of(context).colorScheme.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              initialValue: _credit,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Поступление'),
              items: [
                for (final t in credits)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(_title(t), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _credit = v),
            ),
            DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(16),
              dropdownColor: Theme.of(context).colorScheme.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              key: ValueKey('fee-${debit?.accountId}'),
              initialValue:
                  debit != null &&
                      debits.any(
                        (t) =>
                            t.id == _fee &&
                            t.accountId == debit.accountId &&
                            t.id != debit.id,
                      )
                  ? _fee
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Комиссия (необязательно)',
              ),
              items: [
                for (final t in debits.where(
                  (t) =>
                      debit != null &&
                      t.accountId == debit.accountId &&
                      t.id != debit.id,
                ))
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(_title(t), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _fee = v),
            ),
            if (debit != null && credit != null)
              Text('${_title(debit)} → ${_title(credit)}'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  debit == null ||
                  credit == null ||
                  debit.accountId == credit.accountId
              ? null
              : () async {
                  if (_owner == null ||
                      ref.read(authNavigationProvider).userId != _owner) {
                    return;
                  }
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    await ref
                        .read(transfersRepositoryProvider)
                        .confirm(
                          debit.id,
                          credit.id,
                          debitVersion: debit.updatedAt,
                          creditVersion: credit.updatedAt,
                          feeVersion: debits
                              .where(
                                (t) =>
                                    t.id == _fee &&
                                    t.accountId == debit.accountId &&
                                    t.id != debit.id,
                              )
                              .firstOrNull
                              ?.updatedAt,
                          fee:
                              debits.any(
                                (t) =>
                                    t.id == _fee &&
                                    t.accountId == debit.accountId &&
                                    t.id != debit.id,
                              )
                              ? _fee
                              : null,
                        );
                    if (context.mounted &&
                        mounted &&
                        ref.read(authNavigationProvider).userId == _owner) {
                      Navigator.pop(context);
                    }
                  } catch (_) {
                    if (mounted &&
                        ref.read(authNavigationProvider).userId == _owner) {
                      setState(
                        () => _error =
                            'Не удалось связать операции. Возможно, они изменились: закройте форму и обновите список.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Подтвердить перевод'),
        ),
      ],
    );
  }
}

class CashTransferForm extends ConsumerStatefulWidget {
  const CashTransferForm({super.key});
  @override
  ConsumerState<CashTransferForm> createState() => _CashTransferFormState();
}

class _CashTransferFormState extends ConsumerState<CashTransferForm> {
  String? _debit, _wallet;
  bool _busy = false;
  String? _error;
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(authNavigationProvider).userId;
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref
            .watch(transactionsProvider)
            .asData
            ?.value
            .where(
              (t) =>
                  t.type == 'expense' &&
                  t.transferGroupId == null &&
                  t.transferFeeGroupId == null,
            )
            .toList() ??
        <TransactionEntry>[];
    final wallets =
        ref
            .watch(accountsProvider)
            .asData
            ?.value
            .where((a) => a.isActive && a.type == 'cash')
            .toList() ??
        <AccountSummary>[];
    final debit = items.where((t) => t.id == _debit).firstOrNull,
        wallet = wallets.where((a) => a.id == _wallet).firstOrNull;
    return AlertDialog(
      title: const Text('Снятие наличных'),
      content: SizedBox(
        width: 550,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Выберите существующее списание и наличный кошелёк в той же валюте. Зачисление будет создано автоматически.',
            ),
            DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(16),
              dropdownColor: Theme.of(context).colorScheme.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              initialValue: _debit,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Операция снятия'),
              items: [
                for (final t in items)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.date} · ${t.accountName} · ${Money.displayStored(t.accountAmount)} ${t.accountCurrency}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _debit = v),
            ),
            DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(16),
              dropdownColor: Theme.of(context).colorScheme.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              initialValue: _wallet,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Наличный кошелёк'),
              items: [
                for (final a in wallets)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.name} · ${a.currency}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _wallet = v),
            ),
            if (debit != null &&
                wallet != null &&
                (debit.accountCurrency != wallet.currency ||
                    debit.accountId == wallet.id))
              const Text('Выберите другой кошелёк с валютой счёта списания.'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  debit == null ||
                  wallet == null ||
                  debit.accountId == wallet.id ||
                  debit.accountCurrency != wallet.currency
              ? null
              : () async {
                  if (_owner == null ||
                      ref.read(authNavigationProvider).userId != _owner) {
                    return;
                  }
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    await ref
                        .read(transfersRepositoryProvider)
                        .cash(
                          debit.id,
                          wallet.id,
                          debitVersion: debit.updatedAt,
                        );
                    if (context.mounted &&
                        mounted &&
                        ref.read(authNavigationProvider).userId == _owner) {
                      Navigator.pop(context);
                    }
                  } catch (_) {
                    if (mounted &&
                        ref.read(authNavigationProvider).userId == _owner) {
                      setState(
                        () => _error =
                            'Не удалось создать перевод. Проверьте операцию и кошелёк.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Подтвердить снятие'),
        ),
      ],
    );
  }
}
