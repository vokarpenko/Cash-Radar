import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/auth_navigation.dart';
import '../accounts/money.dart';
import 'currency_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _signingOut = false;
  bool _saving = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось выйти. Повторите попытку.')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _setCurrency(String value) async {
    setState(() => _saving = true);
    try {
      await ref.read(currencyRepositoryProvider).saveBaseCurrency(value);
      if (mounted) ref.invalidate(baseCurrencyProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить валюту. Повторите попытку.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(baseCurrencyProvider);
    return ListView(
      children: [
        Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Управление приложением и доступом',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: const Text('Основная валюта'),
                subtitle: const Text(
                  'Для будущей аналитики. Остатки счетов не пересчитываются.',
                ),
                trailing: currency.when(
                  skipLoadingOnRefresh: false,
                  skipLoadingOnReload: false,
                  loading: () => const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, s) => TextButton(
                    onPressed: () => ref.invalidate(baseCurrencyProvider),
                    child: const Text('Повторить'),
                  ),
                  data: (value) => DropdownButton<String>(
                    value: supportedCurrencies.contains(value) ? value : null,
                    hint: const Text('Выберите'),
                    items: [
                      for (final code in supportedCurrencies)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null && v != value) _setCurrency(v);
                          },
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Выйти'),
                subtitle: const Text('Завершить сессию на этом устройстве'),
                enabled: !_signingOut,
                onTap: _signingOut ? null : _signOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
