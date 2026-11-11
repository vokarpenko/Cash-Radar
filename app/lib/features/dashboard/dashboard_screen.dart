import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text('Обзор', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6),
      Text(
        'Все ваши финансы в одном месте',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 28),
      Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.radar_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Добро пожаловать в CashRadar',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              const Text(
                'Здесь появится общая картина ваших счетов и операций.',
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => context.go('/accounts'),
                child: const Text('Посмотреть счета'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      Text('Разделы', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Счета'),
          subtitle: const Text('Банки и наличные кошельки'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/accounts'),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Операции'),
          subtitle: const Text('Доходы и расходы'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/transactions'),
        ),
      ),
    ],
  );
}
