import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/auth_navigation.dart';
import 'app/cash_radar_app.dart';
import 'config/app_config.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/secure_session_storage.dart';
import 'health/health_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  final config = AppConfig.fromEnvironment();
  var configurationError = config.validationError;
  HealthCheck? check;
  AuthService? auth;
  final initialRecovery = kIsWeb && Uri.base.queryParameters['recovery'] == '1';

  if (configurationError == null) {
    try {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: kIsWeb ? null : SecureSessionStorage(config.url),
        ),
      );
      auth = SupabaseAuthService(Supabase.instance.client);
      check = () async =>
          await Supabase.instance.client.rpc('cash_radar_health') == 'ok';
    } catch (_) {
      configurationError =
          'Не удалось инициализировать Supabase. Проверьте конфигурацию.';
    }
  }

  runApp(
    CashRadarApp(
      check: check,
      auth: auth,
      configurationError: configurationError,
      initialRecovery: initialRecovery,
    ),
  );
}

class CashRadarApp extends StatelessWidget {
  const CashRadarApp({
    super.key,
    this.check,
    this.auth,
    this.configurationError,
    this.initialRecovery = false,
  });

  final HealthCheck? check;
  final AuthService? auth;
  final String? configurationError;
  final bool initialRecovery;

  @override
  Widget build(BuildContext context) {
    final service = auth;
    if (service == null) {
      return MaterialApp(
        title: 'CashRadar',
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: HealthScreen(
          check: check,
          configurationError: configurationError,
        ),
      );
    }
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(service),
        initialRecoveryProvider.overrideWithValue(initialRecovery),
      ],
      child: const CashRadarRouterApp(),
    );
  }
}
