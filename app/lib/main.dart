import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'health/health_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  var configurationError = config.validationError;
  HealthCheck? check;

  if (configurationError == null) {
    try {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
      );
      check = () async =>
          await Supabase.instance.client.rpc('cash_radar_health') == 'ok';
    } catch (_) {
      configurationError =
          'Не удалось инициализировать Supabase. Проверьте конфигурацию.';
    }
  }

  runApp(CashRadarApp(check: check, configurationError: configurationError));
}

class CashRadarApp extends StatelessWidget {
  const CashRadarApp({super.key, this.check, this.configurationError});

  final HealthCheck? check;
  final String? configurationError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CashRadar',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: HealthScreen(check: check, configurationError: configurationError),
  );
}
