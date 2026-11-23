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
    ref.invalidate(gmailActivityProvider);
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

  Future<void> _repeatImport(ImportBatch batch) async {
    final owner = _navigation.userId;
    final version = _sessionVersion;
    if (owner == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подготовить выписку повторно?'),
        content: const Text(
          'Создадим новый предпросмотр из сохранённой выписки. Существующие операции останутся на месте, возможные совпадения нужно будет проверить перед подтверждением.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подготовить повторно'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _sessionVersion != version ||
        _navigation.userId != owner) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(importsRepositoryProvider).repeat(batch.id);
      if (!mounted ||
          _sessionVersion != version ||
          _navigation.userId != owner) {
        return;
      }
      ref.invalidate(importBatchesProvider);
      ref.invalidate(importDetailProvider(id));
      setState(() => _selectedBatch = id);
    } catch (_) {
      if (mounted &&
          _sessionVersion == version &&
          _navigation.userId == owner) {
        setState(
          () => _error =
              'Не удалось подготовить повторный импорт. Проверьте счёт и попробуйте снова.',
        );
      }
    } finally {
      if (mounted && _sessionVersion == version) setState(() => _busy = false);
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
    'superseded' => 'Импортирован · подготовлен повторно',
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
    final gmail = ref.watch(gmailActivityProvider(_userId ?? ''));
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
          child: ExpansionTile(
            title: const Text('Выписки из Gmail'),
            childrenPadding: const EdgeInsets.all(16),
            children: [
              gmail.when(
                loading: () => const Text('Загрузка состояния…'),
                error: (_, _) =>
                    const Text('Не удалось загрузить состояние Gmail.'),
                data: (activity) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.lastRun == null
                          ? 'Проверок пока нет.'
                          : 'Последняя проверка: ${_createdAt(activity.lastRun!)}',
                    ),
                    if (activity.lastRun != null)
                      Text(
                        'Писем проверено: ${activity.scanned} · подготовлено файлов: ${activity.prepared} · ошибок: ${activity.failed}',
                      ),
                    if (activity.errorCode != null)
                      Text(switch (activity.errorCode) {
                        'authorization_expired' =>
                          'Доступ к Gmail истёк. Подключите аккаунт заново.',
                        'mailbox_mismatch' =>
                          'Подключённая почта не совпадает с настроенным адресом.',
                        'unsupported_attachment' =>
                          'В письме нет поддерживаемой XLSX-выписки или есть вложение другого формата.',
                        'unsupported_encrypted' =>
                          'Защищённую выписку можно импортировать вручную.',
                        'acba_password_missing' =>
                          'Не настроен пароль выписки ACBA.',
                        'acba_password_invalid' =>
                          'Пароль выписки ACBA неверный. Обновите секрет.',
                        'invalid_attachment_size' =>
                          'Размер вложения недопустим: максимум 1 МиБ.',
                        'wrong_account' =>
                          'Выписка уже подготовлена для другого счёта.',
                        'rate_limited' =>
                          'Gmail временно ограничил запросы. Проверка повторится позже.',
                        'account_unavailable' =>
                          'Проверьте настройки счёта для выписок.',
                        _ =>
                          'Не удалось проверить Gmail. Проверьте настройки подключения.',
                      }),
                    if (activity.failedAttachments > 0)
                      Text(
                        'Вложений ожидают повторной обработки: ${activity.failedAttachments}.',
                      ),
                    const Text(
                      'Подготовленные выписки отображаются ниже. Операции импортируются после подтверждения.',
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  ref.invalidate(gmailActivityProvider);
                  ref.invalidate(importBatchesProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить'),
              ),
            ],
          ),
        ),
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
                Text(
                  'Выберите счёт и загрузите выписку, чтобы проверить операции перед импортом.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ameria, ACBA, Альфа-Банк · XLSX или CashRadar CSV · до 1 МиБ и 500 операций',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
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
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    menuMaxHeight: 320,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                if (_file?.isEncryptedOffice == true) ...[
                  const SizedBox(height: 16),
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
                ],
                const SizedBox(height: 12),
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.only(bottom: 8),
                  title: Text('Формат CSV и особенности импорта'),
                  children: [
                    Text(
                      'Банковские операции без категории относятся к прочим доходам или расходам. Блокировки без проводки не создают операцию.',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Для CSV укажите дату в формате ГГГГ-ММ-ДД, тип income или expense и существующую категорию. Суммы — с точкой и не более двух знаков после неё. Для другой валюты заполните account_amount.',
                    ),
                    SizedBox(height: 8),
                    SelectableText(
                      'date,type,amount,currency,account_amount,category,description',
                    ),
                    SelectableText(
                      '2026-11-11,expense,12.34,AMD,,Продукты,Покупка',
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
                  'Предпросмотр выписки',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  batch.filename,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ImportTag(
                      label: _status(batch.status),
                      icon: Icons.fact_check_outlined,
                    ),
                    _ImportTag(
                      label: account == null
                          ? 'Счёт недоступен'
                          : '${account.name} · ${batch.accountCurrency}',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    if (batch.periodStart != null && batch.periodEnd != null)
                      _ImportTag(
                        label: '${batch.periodStart} — ${batch.periodEnd}',
                        icon: Icons.date_range_outlined,
                      ),
                    _ImportTag(
                      label: switch (batch.format) {
                        'ameria_xlsx_v1' => 'Ameria XLSX',
                        'acba_xlsx_v1' => 'ACBA XLSX',
                        'alfa_xlsx_v1' => 'Альфа-Банк XLSX',
                        _ => 'CashRadar CSV',
                      },
                      icon: Icons.description_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (batch.status == 'ready' && !accountAvailable)
                  const Text(
                    'Подтверждение недоступно: счёт архивирован, недоступен или его валюта изменилась.',
                  ),
                if (batch.status == 'ready' && accountAvailable && !canConfirm)
                  const Text(
                    'Для подтверждения проверьте решения по возможным совпадениям.',
                  ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ImportMetric(label: 'Строк', value: '${batch.rowCount}'),
                    _ImportMetric(
                      label: 'Ошибок',
                      value: '${batch.errorCount}',
                      isError: batch.errorCount > 0,
                    ),
                    _ImportMetric(
                      label: 'Импортировано',
                      value: '${batch.importedCount}',
                    ),
                    _ImportMetric(
                      label: 'Пропущено',
                      value: '${batch.duplicateCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (batch.format == 'alfa_xlsx_v1')
                  const Text(
                    'Показана сумма по счёту. Сумма и валюта покупки в этой выписке отдельно не указаны.',
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
                    (batch.format == 'ameria_xlsx_v1' ||
                        batch.format == 'acba_xlsx_v1'))
                  AiImportPanel(
                    key: ValueKey(batch.id),
                    batchId: batch.id,
                    completed: batch.status == 'completed',
                  ),
                if (data.rows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Операции',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                ],
                for (final row in data.rows)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: row.needsReview
                            ? Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.45)
                            : Theme.of(context).colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${row.type == 'income' ? '+' : '−'}${Money.formatStored(row.amount)} ${row.currency}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: row.type == 'income'
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                            ),
                            _ImportTag(
                              label: row.category,
                              icon: Icons.sell_outlined,
                            ),
                            Text(
                              row.date,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          row.description?.isNotEmpty == true
                              ? row.description!
                              : (row.type == 'income' ? 'Доход' : 'Расход'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Строка ${row.rowNumber}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (row.postingDate != null)
                          Text(
                            'Дата проводки: ${row.postingDate} · код: ${row.bankOperationCode ?? '—'}${row.mcc == null ? '' : ' · MCC: ${row.mcc}'}',
                          ),
                        if (row.categorizationSource != null)
                          Text(
                            'Категория: ${switch (row.categorizationSource) {
                              'rule' => 'автоматически по вашему правилу · запрос к Gemini не нужен',
                              'alias' => 'алиас',
                              'mcc' => 'MCC',
                              'bank' => 'по категории Альфа-Банка',
                              'delivery' => 'автоматически: сервис доставки еды',
                              'history' => 'предыдущее исправление',
                              'ai' => 'автоматически по сохранённому AI-правилу · запрос к Gemini не нужен',
                              'fallback' => 'по умолчанию',
                              _ => 'вручную',
                            }}',
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
                            'Комиссия: −${Money.formatStored(row.commissionAmount!)} ${batch.accountCurrency} · отдельная операция',
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
                    'Строка ${row.rowNumber}, по счёту: ${Money.formatStored(row.accountAmount)} ${batch.accountCurrency}',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (batch.status == 'completed')
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _repeatImport(batch),
                        icon: const Icon(Icons.replay),
                        label: const Text('Подготовить повторно'),
                      ),
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

class _ImportTag extends StatelessWidget {
  const _ImportTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}

class _ImportMetric extends StatelessWidget {
  const _ImportMetric({
    required this.label,
    required this.value,
    this.isError = false,
  });

  final String label;
  final String value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isError ? theme.colorScheme.onErrorContainer : null,
            ),
          ),
        ],
      ),
    );
  }
}
