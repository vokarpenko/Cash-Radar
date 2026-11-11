import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/section_state.dart';
import 'accounts_repository.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Счета', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Банковские счета и наличные кошельки',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
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
            data: (items) => items.isEmpty
                ? const SectionState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Счетов пока нет',
                    message:
                        'Здесь появятся ваши банковские счета и наличные кошельки.',
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final account = items[index];
                      final type = switch (account.type) {
                        'bank' => account.bankName ?? 'Банковский счёт',
                        'cash' => 'Наличные',
                        _ => 'Кошелёк',
                      };
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              account.type == 'bank'
                                  ? Icons.account_balance_outlined
                                  : Icons.account_balance_wallet_outlined,
                            ),
                          ),
                          title: Text(account.name),
                          subtitle: Text(type),
                          trailing: Text(
                            account.currency,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
