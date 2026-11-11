import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_navigation.dart';

const _destinations = [
  (
    path: '/dashboard',
    label: 'Обзор',
    icon: Icons.space_dashboard_outlined,
    selected: Icons.space_dashboard,
  ),
  (
    path: '/accounts',
    label: 'Счета',
    icon: Icons.account_balance_wallet_outlined,
    selected: Icons.account_balance_wallet,
  ),
  (
    path: '/transactions',
    label: 'Операции',
    icon: Icons.receipt_long_outlined,
    selected: Icons.receipt_long,
  ),
  (
    path: '/settings',
    label: 'Настройки',
    icon: Icons.settings_outlined,
    selected: Icons.settings,
  ),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final index = _destinations.indexWhere((item) => item.path == path);
    final selected = index < 0 ? 0 : index;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final auth = ref.watch(authNavigationProvider);
    void navigate(int value) => context.go(_destinations[value].path);

    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? 40 : 20,
              wide ? 36 : 24,
              wide ? 40 : 20,
              16,
            ),
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: auth,
                  builder: (context, _) => auth.hasError
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Не удалось обновить сессию. Проверьте подключение.',
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: wide ? null : AppBar(title: const Text('CashRadar')),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: navigate,
                  extended: MediaQuery.sizeOf(context).width >= 1000,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Icon(Icons.radar_rounded, size: 32),
                  ),
                  destinations: [
                    for (final item in _destinations)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selected),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: navigate,
              destinations: [
                for (final item in _destinations)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selected),
                    label: item.label,
                  ),
              ],
            ),
    );
  }
}
