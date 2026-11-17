import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';
import '../notifications/notification_bridge.dart';
import '../../app/auth_navigation.dart';
import '../accounts/money.dart';
import '../categorization/rules_screen.dart';
import 'currency_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _signingOut = false;
  bool _saving = false;
  bool _notificationBusy = false;
  NotificationCollectorStatus? _notificationStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadNotificationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadNotificationStatus();
  }

  Future<void> _loadNotificationStatus() async {
    if (!NotificationBridge.supported) return;
    try {
      final status = await NotificationBridge.status();
      if (mounted) setState(() => _notificationStatus = status);
    } catch (_) {
      if (mounted) setState(() => _notificationStatus = null);
    }
  }

  Future<void> _changeNotificationSetting() async {
    setState(() => _notificationBusy = true);
    try {
      final status = await NotificationBridge.status();
      if (!status.permission) {
        await NotificationBridge.openSettings();
      } else if (status.enabled) {
        await NotificationBridge.disable(Supabase.instance.client);
      } else {
        final owner = ref.read(authNavigationProvider).userId;
        if (owner == null) throw StateError('Session unavailable');
        await NotificationBridge.enable(
          Supabase.instance.client,
          owner,
          AppConfig.fromEnvironment(),
        );
      }
      await _loadNotificationStatus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось изменить настройку уведомлений. Попробуйте ещё раз.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  Future<void> _revokeAllNotificationDevices() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отключить все устройства?'),
        content: const Text(
          'Сбор уведомлений прекратится на всех Android-устройствах. Его можно включить заново на каждом из них.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('revoke_all_notification_devices');
      await NotificationBridge.syncOwner(null);
      await _loadNotificationStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сбор уведомлений на устройствах отключён.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось отключить устройства. Попробуйте ещё раз.',
            ),
          ),
        );
      }
    }
  }

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
                leading: const Icon(Icons.rule),
                title: const Text('Правила категорий'),
                subtitle: const Text(
                  'Названия, алиасы, MCC и запомненные исправления',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const RulesDialog(),
                ),
              ),
              const Divider(height: 1),
              if (NotificationBridge.supported) ...[
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Уведомления об операциях'),
                  subtitle: Text(
                    _notificationStatus == null
                        ? 'Проверяем доступ…'
                        : !_notificationStatus!.permission
                        ? 'Нужен доступ к уведомлениям в настройках Android.'
                        : _notificationStatus!.enabled
                        ? 'Включено. В очереди: ${_notificationStatus!.queued}.${_notificationStatus!.dropped > 0 ? ' Пропущено из-за переполнения: ${_notificationStatus!.dropped}.' : ''}'
                        : 'Доступ выдан. Включите сбор в CashRadar.',
                  ),
                  trailing: TextButton(
                    onPressed: _notificationBusy || _notificationStatus == null
                        ? null
                        : _changeNotificationSetting,
                    child: Text(
                      _notificationStatus?.permission != true
                          ? 'Настроить'
                          : _notificationStatus?.enabled == true
                          ? 'Выключить'
                          : 'Включить',
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Android предоставляет доступ ко всем уведомлениям. CashRadar обрабатывает только Google Wallet, My Ameria и acba digital; сообщения и коды подтверждения не обрабатываются. Операции предварительные и не меняют остатки.',
                  ),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const Icon(Icons.phonelink_erase),
                title: const Text('Отключить сбор на всех устройствах'),
                subtitle: const Text(
                  'Отозвать доступ Android-устройств к отправке уведомлений',
                ),
                onTap: _revokeAllNotificationDevices,
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
