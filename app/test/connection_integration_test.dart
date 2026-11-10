import 'package:cash_radar/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const runIntegration = bool.fromEnvironment('RUN_SUPABASE_INTEGRATION_TESTS');

  test(
    'reaches PostgreSQL through the configured Supabase Data API',
    () async {
      final config = AppConfig.fromEnvironment();
      expect(config.validationError, isNull);
      final client = SupabaseClient(config.url, config.publishableKey);
      addTearDown(client.dispose);
      final result = await client
          .rpc('cash_radar_health')
          .timeout(const Duration(seconds: 15));
      expect(result, 'ok');
    },
    skip: runIntegration
        ? false
        : 'Requires explicit opt-in and project config',
  );
}
