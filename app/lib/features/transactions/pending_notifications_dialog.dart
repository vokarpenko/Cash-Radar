import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_navigation.dart';
import '../accounts/money.dart';
import 'transactions_repository.dart';

class PendingNotificationsDialog extends ConsumerStatefulWidget {
  const PendingNotificationsDialog({required this.owner, super.key});
  final String owner;

  @override
  ConsumerState<PendingNotificationsDialog> createState() =>
      _PendingNotificationsDialogState();
}

class _PendingNotificationsDialogState
    extends ConsumerState<PendingNotificationsDialog> {
  late final AuthNavigation _navigation;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _navigation = ref.read(authNavigationProvider);
    _navigation.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_navigation.userId == widget.owner) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _navigation.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _dismiss(PendingNotification item) async {
    if (_navigation.userId != widget.owner) return;
    setState(() => _busy.add(item.id));
    try {
      await ref
          .read(transactionsRepositoryProvider)
          .dismissNotification(item.id);
      if (mounted && _navigation.userId == widget.owner) {
        ref.invalidate(pendingNotificationsProvider(widget.owner));
      }
    } catch (_) {
      if (mounted && _navigation.userId == widget.owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось скрыть уведомление.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingNotificationsProvider(widget.owner));
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 620,
        height: math.min(640, MediaQuery.sizeOf(context).height * .8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Предварительные уведомления',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                'Пока не влияют на остатки. Уведомления банка и Wallet могут относиться к одной покупке.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pending.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(
                      pendingNotificationsProvider(widget.owner),
                    ),
                    child: const Text('Не удалось загрузить. Повторить'),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('Новых уведомлений нет'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 24, endIndent: 24),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final kind = switch (item.kind) {
                            'pre_purchase' => 'Холд',
                            'pre_purchase_completion' => 'Завершение холда',
                            'credit' => 'Зачисление или перевод',
                            _ => 'Покупка',
                          };
                          final source = switch (item.source) {
                            'wallet' => 'Google Wallet',
                            'ameria' => 'My Ameria',
                            'acba' => 'acba digital',
                            _ => item.source,
                          };
                          final date = DateTime.tryParse(
                            item.occurredAt,
                          )?.toLocal();
                          final when = date == null
                              ? item.occurredAt
                              : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.merchant,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$kind · $source · ••${item.cardLast4}',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$when${item.timeSource == 'notification' ? ' · время уведомления' : ''}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${Money.displayStored(item.amount)} ${item.currency}',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Скрыть уведомление',
                                  onPressed: _busy.contains(item.id)
                                      ? null
                                      : () => _dismiss(item),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
