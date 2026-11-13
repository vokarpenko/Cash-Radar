import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import '../accounts/accounts_repository.dart';
import '../accounts/money.dart';
import '../categorization/ai_panel.dart';
import '../transactions/transactions_repository.dart';
import 'import_repository.dart';

class ImportsScreen extends ConsumerStatefulWidget {
  const ImportsScreen({super.key});
  @override
  ConsumerState<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends ConsumerState<ImportsScreen> {
  late final AuthNavigation _navigation;
  String? _userId, _accountId, _selectedBatch;
  SelectedStatement? _file;
  final _password = TextEditingController();
  bool _busy = false;
  int _sessionVersion = 0;
  String? _error;

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
    _sessionVersion++;
    _password.clear();
    setState(() {
      _file = null;
      _accountId = null;
      _selectedBatch = null;
      _error = null;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _navigation.removeListener(_onSessionChanged);
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final owner = _navigation.userId;
    final version = _sessionVersion;
    if (owner == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(statementFilePickerProvider).pick();
      if (!mounted ||
          _sessionVersion != version ||
          _navigation.userId != owner) {
        return;
      }
      if (result != null) {
        _password.clear();
        setState(() => _file = result);
      }
    } on ImportProblem catch (e) {
      if (mounted &&
          _sessionVersion == version &&
          _navigation.userId == owner) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted &&
          _sessionVersion == version &&
          _navigation.userId == owner) {
        setState(() => _error = 'Не удалось выбрать файл. Повторите попытку.');
      }
    } finally {
      if (mounted && _sessionVersion == version) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() async {
    final owner = _navigation.userId, account = _accountId, file = _file;
    final version = _sessionVersion;
    if (owner == null || account == null || file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(importsRepositoryProvider)
          .prepare(
            account,
            file,
            owner,
            password: file.isEncryptedOffice ? _password.text : null,
          );
      if (!mounted ||
          _sessionVersion != version ||
          _navigation.userId != owner) {
        return;
      }
      _password.clear();
      setState(() {
        _file = null;
        _selectedBatch = result.id;
      });
      ref.invalidate(importBatchesProvider);
      ref.invalidate(importDetailProvider(result.id));
      if (result.duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Этот файл уже подготовлен или импортирован. Открыт существующий импорт.',
            ),
          ),
        );
      }
    } on ImportProblem catch (e) {
      if (mounted &&
          _sessionVersion == version &&
          _navigation.userId == owner) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted &&
          _sessionVersion == version &&
          _navigation.userId == owner) {
        setState(
          () =>
              _error = 'Не удалось подготовить импорт. Проверьте подключение.',
        );
      }
    } finally {
      if (mounted && _sessionVersion == version) setState(() => _busy = false);
    }
  }

  Future<void> _reapplyCategories(String batchId) async {
    final owner = _navigation.userId, version = _sessionVersion;
    if (owner == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(importsRepositoryProvider).reapplyCategories(batchId);
      if (mounted &&
          version == _sessionVersion &&
          owner == _navigation.userId) {
        ref.invalidate(importDetailProvider(batchId));
      }
    } catch (_) {
      if (mounted &&
          version == _sessionVersion &&
          owner == _navigation.userId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось применить правила. Повторите попытку.'),
          ),
        );
      }
    } finally {
      if (mounted && version == _sessionVersion) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(ImportRow row, String decision, String batchId) async {
    final version = _sessionVersion;
    final owner = _navigation.userId;
    if (row.id == null || owner == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(importsRepositoryProvider)
          .resolveDuplicate(row.id!, decision);
      if (mounted &&
          version == _sessionVersion &&
          owner == _navigation.userId) {
        ref.invalidate(importDetailProvider(batchId));
      }
    } catch (_) {
      if (mounted &&
          version == _sessionVersion &&
          owner == _navigation.userId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить решение. Обновите предпросмотр.',
            ),
          ),
        );
        ref.invalidate(importDetailProvider(batchId));
      }
    } finally {
      if (mounted && version == _sessionVersion) setState(() => _busy = false);
    }
  }

  Future<void> _apply(
    ImportBatch batch, {
    required bool cancel,
    int skipped = 0,
    int fees = 0,
  }) async {
    final owner = _navigation.userId;
    final version = _sessionVersion;
    if (owner == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(cancel ? 'Отменить подготовку?' : 'Подтвердить импорт?'),
        content: Text(
          cancel
              ? 'Подготовленные строки будут удалены. Оригинал останется в закрытом хранилище.'
              : 'Будет добавлено операций: ${batch.rowCount - skipped + fees}, из них комиссий: $fees. Пропущено строк: $skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(cancel ? 'Отменить подготовку' : 'Подтвердить'),
          ),
        ],
      ),
    );
    if (!mounted ||
        approved != true ||
        _sessionVersion != version ||
        _navigation.userId != owner) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(importsRepositoryProvider);
      if (cancel) {
        await repo.cancel(batch.id);
      } else {
        await repo.confirm(batch.id);
      }
      if (!mounted ||
          _sessionVersion != version ||
          _navigation.userId != owner) {
        return;
      }
      ref.invalidate(importBatchesProvider);
      ref.invalidate(importDetailProvider(batch.id));
      if (!cancel) {
        ref.invalidate(transactionsProvider);
        ref.invalidate(accountsProvider);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancel ? 'Подготовка отменена.' : 'Импорт подтверждён.',
          ),
        ),
      );
    } catch (_) {
      if (mounted &&
          _sessionVersion == version &&
          _navigation.userId == owner) {
        setState(
          () => _error =
              'Не удалось изменить импорт. Проверьте состояние счёта и попробуйте снова.',
        );
        ref.invalidate(importBatchesProvider);
        ref.invalidate(importDetailProvider(batch.id));
      }
    } finally {
      if (mounted && _sessionVersion == version) setState(() => _busy = false);
    }
  }

  String _status(String status) => switch (status) {
    'ready' => 'Готов к подтверждению',
    'invalid' => 'Ошибки в файле',
    'completed' => 'Импортирован',
    'cancelled' => 'Отменён',
    _ => 'Неизвестный статус',
  };

  String _createdAt(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final batches = ref.watch(importBatchesProvider);
    final active =
        accounts.asData?.value.where((a) => a.isActive).toList() ?? [];
    final chosen = active.where((a) => a.id == _accountId).firstOrNull;
    return ListView(
      children: [
        Text('Импорт', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text('Подготовьте файл, проверьте строки и подтвердите импорт.'),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Новый импорт',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Поддерживаются CashRadar CSV, Ameria XLSX и ACBA XLSX: до 1 МиБ и 500 операций. Категории банковских операций — «Прочие доходы» и «Прочие расходы». Снятие блокировки без проводки не создаёт операцию. Проверяйте пересечения с уже внесёнными операциями.',
                ),
                const SizedBox(height: 8),
                if (_file?.isEncryptedOffice == true)
                  TextField(
                    controller: _password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 255,
                    decoration: const InputDecoration(
                      labelText: 'Пароль от файла ACBA',
                      helperText:
                          'Пароль используется только для этой загрузки и не сохраняется.',
                    ),
                  ),
                const SelectableText(
                  'date,type,amount,currency,account_amount,category,description',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Дата — ГГГГ-ММ-ДД, тип — income или expense, категория должна совпадать с вашей категорией. Суммы указывайте с точкой и не более чем двумя знаками после неё. Для другой валюты обязательно заполните account_amount.',
                ),
                const SelectableText(
                  '2026-11-11,expense,12.34,AMD,,Продукты,Покупка',
                  style: TextStyle(fontSize: 12),
                ),
                accounts.when(
                  skipLoadingOnRefresh: false,
                  skipLoadingOnReload: false,
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, s) => TextButton(
                    onPressed: () => ref.invalidate(accountsProvider),
                    child: const Text('Не удалось загрузить счета. Повторить'),
                  ),
                  data: (_) => DropdownButtonFormField<String>(
                    key: ValueKey('import-account-${chosen?.id}'),
                    initialValue: chosen?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Счёт для импорта',
                    ),
                    items: [
                      for (final a in active)
                        DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            '${a.name} · ${a.currency}${a.bankName == null ? '' : ' · ${a.bankName}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _accountId = v),
                  ),
                ),
                if (accounts.hasValue && active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Сначала добавьте активный счёт.'),
                  ),
                if (chosen != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Банк: ${chosen.bankName ?? 'не указан для кошелька'} · валюта счёта: ${chosen.currency}',
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Выбрать файл'),
                    ),
                    if (_file != null) Text(_file!.name),
                    FilledButton(
                      onPressed: _busy || chosen == null || _file == null
                          ? null
                          : _prepare,
                      child: Text(_busy ? 'Обработка…' : 'Подготовить импорт'),
                    ),
                  ],
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
        const SizedBox(height: 20),
        if (_selectedBatch != null) ...[
          _detail(_selectedBatch!),
          const SizedBox(height: 20),
        ],
        Text('История импортов', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        batches.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, s) => TextButton(
            onPressed: () => ref.invalidate(importBatchesProvider),
            child: const Text('Не удалось загрузить историю. Повторить'),
          ),
          data: (items) => items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Импортов пока нет.'),
                )
              : Column(
                  children: [
                    for (final batch in items)
                      Card(
                        child: ListTile(
                          title: Text(batch.filename),
                          subtitle: Text(
                            '${_status(batch.status)} · ${_createdAt(batch.createdAt)} · строк: ${batch.rowCount} · ошибок: ${batch.errorCount}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              setState(() => _selectedBatch = batch.id),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _detail(String id) {
    final detail = ref.watch(importDetailProvider(id));
    final accounts = ref.watch(accountsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: detail.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => TextButton(
            onPressed: () => ref.invalidate(importDetailProvider(id)),
            child: const Text('Не удалось загрузить предпросмотр. Повторить'),
          ),
          data: (data) {
            final batch = data.batch;
            final account = accounts.asData?.value
                .where((a) => a.id == batch.accountId)
                .firstOrNull;
            final accountAvailable =
                account != null &&
                account.isActive &&
                account.currency == batch.accountCurrency;
            final canConfirm =
                accountAvailable && data.rows.every((r) => !r.needsReview);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Предпросмотр: ${batch.filename}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_status(batch.status)} · формат: ${batch.format == 'ameria_xlsx_v1'
                      ? 'Ameria XLSX'
                      : batch.format == 'acba_xlsx_v1'
                      ? 'ACBA XLSX'
                      : 'CashRadar CSV'} · валюта счёта: ${batch.accountCurrency}',
                ),
                Text(
                  account == null
                      ? 'Счёт недоступен.'
                      : 'Счёт: ${account.name} · ${account.bankName ?? 'кошелёк'}',
                ),
                if (batch.periodStart != null && batch.periodEnd != null)
                  Text('Период: ${batch.periodStart} — ${batch.periodEnd}'),
                if (batch.status == 'ready' && !accountAvailable)
                  const Text(
                    'Подтверждение недоступно: счёт архивирован, недоступен или его валюта изменилась.',
                  ),
                if (batch.status == 'ready' && accountAvailable && !canConfirm)
                  const Text(
                    'Для подтверждения проверьте решения по возможным совпадениям.',
                  ),
                Text(
                  'Корректных строк: ${batch.rowCount} · ошибок: ${batch.errorCount} · импортировано: ${batch.importedCount} · пропущено: ${batch.duplicateCount}',
                ),
                if (batch.status == 'invalid')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Исправьте файл или настройки счёта и загрузите его снова. Частичный импорт не выполняется.',
                    ),
                  ),
                for (final issue in batch.errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Строка ${issue.row}: ${issue.message}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (batch.errorCount > batch.errors.length)
                  Text(
                    'Показаны первые ${batch.errors.length} ошибок из ${batch.errorCount}.',
                  ),
                if ((batch.status == 'ready' || batch.status == 'completed') &&
                    batch.format != 'cashradar_csv_v1')
                  AiImportPanel(
                    key: ValueKey(batch.id),
                    batchId: batch.id,
                    completed: batch.status == 'completed',
                  ),
                for (final row in data.rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.description?.isNotEmpty == true
                              ? row.description!
                              : (row.type == 'income' ? 'Доход' : 'Расход'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Строка ${row.rowNumber} · ${row.date} · ${row.category}',
                        ),
                        if (row.categorizationSource != null)
                          Text(
                            'Категория: ${switch (row.categorizationSource) {
                              'rule' => 'правило',
                              'alias' => 'алиас',
                              'mcc' => 'MCC',
                              'history' => 'предыдущее исправление',
                              'ai' => 'AI-соответствие',
                              'fallback' => 'по умолчанию',
                              _ => 'вручную',
                            }}',
                          ),
                        Text(
                          '${row.type == 'income' ? '+' : '−'}${Money.displayStored(row.amount)} ${row.currency}',
                        ),
                        if (batch.status == 'ready' &&
                            (row.candidates.isNotEmpty ||
                                row.duplicateDecision != null)) ...[
                          Text(
                            row.needsReview
                                ? 'Возможное совпадение — проверьте строку'
                                : 'Решение: ${row.duplicateDecision == 'skip' ? 'пропустить' : 'импортировать'}',
                          ),
                          for (final candidate in row.candidates)
                            Text(
                              candidate.type == 'file'
                                  ? 'В этом файле: строка ${candidate.rowNumber} · ${candidate.date} · ${candidate.description ?? ''}'
                                  : 'В операциях: ${candidate.date} · ${candidate.description ?? ''} · ${candidate.source == 'manual' ? 'вручную' : 'выписка'}',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (row.candidates.isNotEmpty) ...[
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(row, 'skip', batch.id),
                                  child: const Text('Пропустить строку'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(row, 'keep', batch.id),
                                  child: const Text('Импортировать строку'),
                                ),
                              ] else
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(row, 'clear', batch.id),
                                  child: const Text('Сбросить решение'),
                                ),
                            ],
                          ),
                        ],
                        if (row.commissionAmount != null)
                          Text(
                            'Комиссия: −${Money.displayStored(row.commissionAmount!)} ${batch.accountCurrency} · отдельная операция',
                          ),
                      ],
                    ),
                  ),
                if (data.rows.any((r) => r.currency != batch.accountCurrency))
                  const Text(
                    'Для разных валют будет использована указанная в файле фактическая сумма по счёту.',
                  ),
                for (final row in data.rows.where(
                  (r) => r.currency != batch.accountCurrency,
                ))
                  Text(
                    'Строка ${row.rowNumber}, по счёту: ${Money.displayStored(row.accountAmount)} ${batch.accountCurrency}',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (batch.status == 'ready' &&
                        batch.format != 'cashradar_csv_v1')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _reapplyCategories(batch.id),
                        child: const Text('Применить правила категорий'),
                      ),
                    if (batch.status == 'ready')
                      FilledButton(
                        onPressed: _busy || !canConfirm
                            ? null
                            : () => _apply(
                                batch,
                                cancel: false,
                                skipped: data.rows
                                    .where((r) => r.duplicateDecision == 'skip')
                                    .length,
                                fees: data.rows
                                    .where(
                                      (r) =>
                                          r.duplicateDecision != 'skip' &&
                                          r.commissionAmount != null,
                                    )
                                    .length,
                              ),
                        child: const Text('Подтвердить импорт'),
                      ),
                    if (batch.status == 'ready' || batch.status == 'invalid')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _apply(batch, cancel: true),
                        child: const Text('Отменить подготовку'),
                      ),
                    TextButton(
                      onPressed: () => setState(() => _selectedBatch = null),
                      child: const Text('Закрыть предпросмотр'),
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
