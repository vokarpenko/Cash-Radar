import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/section_state.dart';
import 'account_form.dart';
import 'accounts_repository.dart';
import 'money.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});
  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool _showArchived = false;
  final Set<String> _busy = {};

  Future<void> _edit([AccountSummary? account]) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => AccountForm(account: account),
    );
  }

  Future<void> _toggleActive(AccountSummary account) async {
    if (account.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Архивировать счёт?'),
          content: Text(
            '«${account.name}» исчезнет из списка активных счетов. Его можно будет восстановить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Архивировать'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy.add(account.id));
    try {
      await ref
          .read(accountsRepositoryProvider)
          .setActive(account.id, !account.isActive);
      if (mounted) ref.invalidate(accountsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось изменить статус счёта. Повторите попытку.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(account.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
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
                  'Счета',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Банковские счета и наличные кошельки',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Добавить счёт'),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Показать архивные'),
          value: _showArchived,
          onChanged: (v) => setState(() => _showArchived = v),
        ),
        Expanded(
          child: accounts.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => SectionState(
              icon: Icons.cloud_off_outlined,
              title: 'Не удалось загрузить счета',
              message:
                  'Проверьте подключение к интернету и попробуйте ещё раз.',
              action: OutlinedButton(
                onPressed: () => ref.invalidate(accountsProvider),
                child: const Text('Повторить'),
              ),
            ),
            data: (all) {
              final items = all
                  .where((a) => _showArchived || a.isActive)
                  .toList();
              if (items.isEmpty) {
                return const SectionState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Счетов пока нет',
                  message: 'Добавьте банковский счёт или наличный кошелёк.',
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final account = items[index];
                  final type = switch (account.type) {
                    'bank' => account.bankName ?? 'Банковский счёт',
                    'cash' => 'Наличные',
                    _ => 'Кошелёк',
                  };
                  final balance = Money.displayStored(account.currentBalance);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Icon(
                                account.type == 'bank'
                                    ? Icons.account_balance_outlined
                                    : Icons.account_balance_wallet_outlined,
                              ),
                            ),
                            title: Text(account.name),
                            subtitle: Text(
                              '$type${account.isActive ? '' : ' · В архиве'}',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '$balance ${account.currency}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: _busy.contains(account.id)
                                    ? null
                                    : () => _edit(account),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Изменить'),
                              ),
                              TextButton.icon(
                                onPressed: _busy.contains(account.id)
                                    ? null
                                    : () => _toggleActive(account),
                                icon: Icon(
                                  account.isActive
                                      ? Icons.archive_outlined
                                      : Icons.unarchive_outlined,
                                ),
                                label: Text(
                                  account.isActive ? 'В архив' : 'Восстановить',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
