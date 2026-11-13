import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/auth_navigation.dart';
import '../imports/import_repository.dart';
import '../transactions/transactions_repository.dart';

class AiImportPanel extends ConsumerStatefulWidget {
  const AiImportPanel({
    super.key,
    required this.batchId,
    required this.completed,
  });
  final String batchId;
  final bool completed;
  @override
  ConsumerState<AiImportPanel> createState() => _AiImportPanelState();
}

class _AiImportPanelState extends ConsumerState<AiImportPanel> {
  SupabaseClient get _client => Supabase.instance.client;
  final Set<String> _selected = {};
  List<Map<String, dynamic>>? _candidates;
  bool _busy = false;
  String? _error, _message;
  String? _owner;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(authNavigationProvider).userId;
    _load();
  }

  bool get _sameUser =>
      mounted &&
      _owner != null &&
      ref.read(authNavigationProvider).userId == _owner;
  Future<void> _load() async {
    try {
      final result =
          await _client.rpc(
                'ai_import_candidates',
                params: {'p_batch_id': widget.batchId},
              )
              as List;
      if (!_sameUser) return;
      setState(() {
        _candidates = result
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        _selected.clear();
      });
    } catch (_) {
      if (_sameUser) {
        setState(() => _error = 'Не удалось получить список названий.');
      }
    }
  }

  Future<void> _send() async {
    final entries = _candidates!
        .where((c) => _selected.contains(c['group_id']))
        .toList();
    if (entries.isEmpty || entries.length > 10 || !_sameUser) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final session = _client.auth.currentSession;
      if (session == null || session.user.id != _owner) return;
      final response = await _client.functions.invoke(
        'categorize-merchant',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'batch_id': widget.batchId,
          'groups': [
            for (final c in entries)
              {'group_id': c['group_id'], 'merchant': c['merchant']},
          ],
        },
      );
      if (!_sameUser) return;
      final data = response.data as Map;
      setState(
        () => _message =
            'Создано правил: ${data['rules']}; предложений для проверки: ${data['suggestions']}.',
      );
      ref.invalidate(importDetailProvider(widget.batchId));
      await _load();
    } on FunctionException catch (e) {
      if (_sameUser) {
        setState(
          () =>
              _error = e.details is Map && (e.details as Map)['error'] is String
              ? (e.details as Map)['error'] as String
              : 'Не удалось получить ответ AI.',
        );
      }
    } catch (_) {
      if (_sameUser) {
        setState(() => _error = 'Не удалось выполнить AI-категоризацию.');
      }
    } finally {
      if (_sameUser) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _candidates;
    return ExpansionTile(
      title: const Text('Категоризация с Gemini'),
      subtitle: const Text('Выберите публичные названия для проверки'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        const Text(
          'Google получит только выбранные названия и тип операции. На бесплатном тарифе Google может использовать запросы для улучшения сервисов; название может раскрывать сведения о покупке. Не выбирайте личные данные или номера.',
        ),
        if (widget.completed)
          const Text(
            'Созданные правила применятся к следующим импортам. Уже импортированные операции автоматически не изменятся.',
          ),
        if (rows == null && _error == null) const CircularProgressIndicator(),
        if (rows != null && rows.isEmpty)
          const Text('Неизвестных названий для проверки нет.'),
        if (rows != null)
          for (final c in rows)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selected.contains(c['group_id']),
              title: Text(c['merchant'] as String),
              subtitle: Text(
                '${c['kind'] == 'income' ? 'Доход' : 'Расход'} · операций: ${c['item_count']}',
              ),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      if (value == true && _selected.length < 10) {
                        _selected.add(c['group_id'] as String);
                      }
                      if (value == false) {
                        _selected.remove(c['group_id']);
                      }
                    }),
            ),
        if (rows != null && rows.isNotEmpty)
          FilledButton.tonal(
            onPressed: _busy || _selected.isEmpty ? null : _send,
            child: Text(
              _busy
                  ? 'Обработка…'
                  : 'Отправить выбранные (${_selected.length}/10)',
            ),
          ),
        if (_message != null) Text(_message!),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class AiRulesPanel extends ConsumerStatefulWidget {
  const AiRulesPanel({super.key, required this.categories});
  final List<TransactionCategory> categories;
  @override
  ConsumerState<AiRulesPanel> createState() => _AiRulesPanelState();
}

class _AiRulesPanelState extends ConsumerState<AiRulesPanel> {
  SupabaseClient get _client => Supabase.instance.client;
  List<Map<String, dynamic>>? _rules, _suggestions;
  bool _busy = false;
  String? _owner, _error;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(authNavigationProvider).userId;
    _load();
  }

  bool get _sameUser =>
      mounted &&
      _owner != null &&
      ref.read(authNavigationProvider).userId == _owner;
  Future<void> _load() async {
    try {
      final rules = await _client
          .from('ai_merchant_rules')
          .select()
          .order('merchant_name');
      final suggestions = await _client
          .from('ai_suggestions')
          .select()
          .eq('status', 'pending')
          .order('merchant_name');
      if (_sameUser) {
        setState(() {
          _rules = rules;
          _suggestions = suggestions;
        });
      }
    } catch (_) {
      if (_sameUser) {
        setState(() => _error = 'Не удалось загрузить AI-правила.');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_sameUser) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (_) {
      if (_sameUser) setState(() => _error = 'Не удалось сохранить изменение.');
    } finally {
      if (_sameUser) setState(() => _busy = false);
    }
  }

  String _category(String? id) =>
      widget.categories
          .where((c) => c.id == id)
          .map((c) => c.name)
          .firstOrNull ??
      'Категория недоступна';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      Text('AI-соответствия', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Точное совпадение названия; ваши правила и исправления имеют приоритет.',
      ),
      if (_error != null) Text(_error!),
      if (_rules == null && _error == null) const CircularProgressIndicator(),
      if (_rules != null && _rules!.isEmpty)
        const Text('Соответствий пока нет.'),
      for (final r in _rules ?? <Map<String, dynamic>>[])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(r['merchant_name'] as String),
          subtitle: DropdownButton<String>(
            value: widget.categories.any((c) => c.id == r['category_id'])
                ? r['category_id'] as String
                : null,
            hint: Text(_category(r['category_id'] as String?)),
            items: [
              for (final c in widget.categories.where(
                (c) => c.kind == r['kind'],
              ))
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: _busy
                ? null
                : (id) {
                    if (id != null) {
                      _run(() async {
                        await _client
                            .from('ai_merchant_rules')
                            .update({'category_id': id})
                            .eq('id', r['id']);
                      });
                    }
                  },
          ),
          leading: Switch(
            value: r['enabled'] as bool,
            onChanged: _busy
                ? null
                : (v) => _run(() async {
                    await _client
                        .from('ai_merchant_rules')
                        .update({'enabled': v})
                        .eq('id', r['id']);
                  }),
          ),
          trailing: IconButton(
            tooltip: 'Удалить соответствие',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await _client
                        .from('ai_merchant_rules')
                        .delete()
                        .eq('id', r['id']);
                  }),
          ),
        ),
      Text('Предложения AI', style: Theme.of(context).textTheme.titleMedium),
      if (_suggestions != null && _suggestions!.isEmpty)
        const Text('Предложений для проверки нет.'),
      for (final s in _suggestions ?? <Map<String, dynamic>>[])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${s['merchant_name']} → ${_category(s['category_id'] as String?)}',
          ),
          subtitle: Text(
            '${s['kind'] == 'income' ? 'Доход' : 'Расход'} · уверенность ${((s['confidence'] as num) * 100).round()}%',
          ),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: 'Принять',
                icon: const Icon(Icons.check),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await _client.rpc(
                          'ai_review_suggestion',
                          params: {'p_id': s['id'], 'p_accept': true},
                        );
                      }),
              ),
              IconButton(
                tooltip: 'Отклонить',
                icon: const Icon(Icons.close),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await _client.rpc(
                          'ai_review_suggestion',
                          params: {'p_id': s['id'], 'p_accept': false},
                        );
                      }),
              ),
            ],
          ),
        ),
    ],
  );
}
