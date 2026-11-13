import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/auth_navigation.dart';
import '../transactions/transactions_repository.dart';
import 'rules_repository.dart';

class RulesDialog extends ConsumerStatefulWidget {
  const RulesDialog({super.key});
  @override
  ConsumerState<RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends ConsumerState<RulesDialog> {
  late final AuthNavigation _nav;
  late final String? _owner;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _nav = ref.read(authNavigationProvider);
    _owner = _nav.userId;
    _nav.addListener(_session);
  }

  void _session() {
    if (_nav.userId == _owner && _nav.hasSession) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _nav.removeListener(_session);
    super.dispose();
  }

  Future<void> _run(Future<void> Function(RulesRepository) action) async {
    if (_busy || _owner == null || _nav.userId != _owner) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(rulesRepositoryProvider));
      if (mounted && _nav.userId == _owner) ref.invalidate(rulesProvider);
    } catch (_) {
      if (mounted && _nav.userId == _owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить правило. Проверьте данные и подключение.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(bool alias, List<TransactionCategory> categories) async {
    final input = await showDialog<_RuleInput>(
      context: context,
      builder: (_) => _RuleEditor(alias: alias, categories: categories),
    );
    if (!mounted || input == null || _nav.userId != _owner) return;
    if (alias) {
      await _run(
        (r) => r.addAlias(
          kind: input.kind,
          alias: input.pattern,
          canonicalName: input.canonical,
          categoryId: input.categoryId,
        ),
      );
    } else {
      await _run(
        (r) => r.addRule(
          kind: input.kind,
          matchType: input.matchType,
          pattern: input.pattern,
          categoryId: input.categoryId!,
          priority: input.priority,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider),
        categories = ref.watch(transactionCategoriesProvider);
    return AlertDialog(
      title: const Text('Правила категорий'),
      content: SizedBox(
        width: 680,
        child: rules.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => TextButton(
            onPressed: () => ref.invalidate(rulesProvider),
            child: const Text('Не удалось загрузить правила. Повторить'),
          ),
          data: (data) => categories.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => TextButton(
              onPressed: () => ref.invalidate(transactionCategoriesProvider),
              child: const Text('Не удалось загрузить категории. Повторить'),
            ),
            data: (cats) {
              String name(String? id) =>
                  cats
                      .where((c) => c.id == id)
                      .map((c) => c.name)
                      .firstOrNull ??
                  'Без категории';
              return ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'Правила применяются к новым банковским выпискам. Чем выше приоритет, тем раньше правило проверяется.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _add(false, cats),
                        child: const Text('Добавить правило'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _add(true, cats),
                        child: const Text('Добавить алиас'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Правила',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (data.rules.isEmpty) const Text('Правил пока нет.'),
                  for (final rule in data.rules)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${rule.pattern} → ${name(rule.categoryId)}'),
                      subtitle: Text(
                        '${rule.kind == 'expense' ? 'Расход' : 'Доход'} · ${rule.matchType == 'mcc'
                            ? 'MCC'
                            : rule.matchType == 'merchant_exact'
                            ? 'Точное название'
                            : 'Содержит'} · приоритет ${rule.priority}',
                      ),
                      leading: Switch(
                        value: rule.enabled,
                        onChanged: _busy
                            ? null
                            : (v) => _run((r) => r.setRuleEnabled(rule.id, v)),
                      ),
                      trailing: IconButton(
                        tooltip: 'Удалить правило',
                        onPressed: _busy
                            ? null
                            : () => _run((r) => r.deleteRule(rule.id)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  const Divider(),
                  Text(
                    'Алиасы',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (data.aliases.isEmpty) const Text('Алиасов пока нет.'),
                  for (final a in data.aliases)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${a.alias} → ${a.canonicalName}'),
                      subtitle: Text(
                        '${a.kind == 'expense' ? 'Расход' : 'Доход'} · ${name(a.categoryId)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Удалить алиас',
                        onPressed: _busy
                            ? null
                            : () => _run((r) => r.deleteAlias(a.id)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  const Divider(),
                  Text(
                    'Запомненные исправления',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Сохраняются при изменении категории существующей операции.',
                  ),
                  if (data.memories.isEmpty)
                    const Text('Исправлений пока нет.'),
                  for (final m in data.memories)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.merchant),
                      subtitle: Text(
                        '${m.kind == 'expense' ? 'Расход' : 'Доход'} · ${name(m.categoryId)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Забыть исправление',
                        onPressed: _busy
                            ? null
                            : () => _run((r) => r.deleteMemory(m.id)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _RuleInput {
  const _RuleInput({
    required this.kind,
    required this.matchType,
    required this.pattern,
    required this.canonical,
    required this.categoryId,
    required this.priority,
  });
  final String kind, matchType, pattern, canonical;
  final String? categoryId;
  final int priority;
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({required this.alias, required this.categories});
  final bool alias;
  final List<TransactionCategory> categories;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  final _form = GlobalKey<FormState>();
  final _pattern = TextEditingController(),
      _canonical = TextEditingController(),
      _priority = TextEditingController(text: '100');
  String _kind = 'expense', _type = 'merchant_contains';
  String? _category;
  @override
  void dispose() {
    _pattern.dispose();
    _canonical.dispose();
    _priority.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories.where((c) => c.kind == _kind).toList();
    return AlertDialog(
      title: Text(widget.alias ? 'Новый алиас' : 'Новое правило'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Тип операции'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Расход')),
                    DropdownMenuItem(value: 'income', child: Text('Доход')),
                  ],
                  onChanged: (v) => setState(() {
                    _kind = v!;
                    _category = null;
                  }),
                ),
                if (!widget.alias)
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Условие'),
                    items: const [
                      DropdownMenuItem(
                        value: 'merchant_contains',
                        child: Text('Название содержит'),
                      ),
                      DropdownMenuItem(
                        value: 'merchant_exact',
                        child: Text('Точное название'),
                      ),
                      DropdownMenuItem(value: 'mcc', child: Text('Код MCC')),
                    ],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                TextFormField(
                  controller: _pattern,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: widget.alias
                        ? 'Исходное название'
                        : _type == 'mcc'
                        ? 'Код MCC'
                        : 'Название или часть названия',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (!widget.alias && _type == 'mcc') {
                      return RegExp(r'^\d{4}$').hasMatch(t)
                          ? null
                          : 'Введите 4 цифры';
                    }
                    return t.length >= 3 ? null : 'Минимум 3 символа';
                  },
                ),
                if (widget.alias)
                  TextFormField(
                    controller: _canonical,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Общее название',
                    ),
                    validator: (v) => (v ?? '').trim().length >= 3
                        ? null
                        : 'Минимум 3 символа',
                  ),
                DropdownButtonFormField<String>(
                  key: ValueKey('rule-cat-$_kind'),
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: widget.alias
                        ? 'Категория (необязательно)'
                        : 'Категория',
                  ),
                  items: [
                    for (final c in cats)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                  validator: (v) =>
                      !widget.alias && v == null ? 'Выберите категорию' : null,
                ),
                if (!widget.alias)
                  TextFormField(
                    controller: _priority,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Приоритет: от 0 до 10000',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 0 || n > 10000
                          ? 'Введите число от 0 до 10000'
                          : null;
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _RuleInput(
                kind: _kind,
                matchType: _type,
                pattern: _pattern.text.trim(),
                canonical: _canonical.text.trim(),
                categoryId: _category,
                priority: int.tryParse(_priority.text) ?? 100,
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
