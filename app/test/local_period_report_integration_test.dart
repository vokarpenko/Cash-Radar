import 'package:cash_radar/features/analytics/analytics_repository.dart';
import 'package:cash_radar/features/analytics/period_report.dart';
import 'package:cash_radar/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/local_supabase.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_LOCAL_PERIOD_REPORT_TESTS');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  test(
    'real local API builds period report with signed balances and transfers',
    () async {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          uri.port != 54321) {
        throw StateError('Only local Supabase is permitted');
      }
      final email =
          'cashradar_period_${DateTime.now().microsecondsSinceEpoch}@example.test';
      final client = SupabaseClient(
        url,
        key,
        authOptions: AuthClientOptions(
          pkceAsyncStorage: MemoryVerifierStorage(),
        ),
      );
      try {
        final auth = SupabaseAuthService(client);
        expect(await auth.signUp(email, 'temporary-pass-123'), isFalse);
        await followLocalMailLink(client, await readLocalMailLink(email));
        final cat = (await client
            .from('categories')
            .select('id')
            .eq('kind', 'expense')
            .limit(1)
            .single())['id'];
        Future<String> account(
          String name,
          String currency,
          String initial,
        ) async =>
            (await client
                    .from('accounts')
                    .insert({
                      'name': name,
                      'account_type': 'cash',
                      'currency': currency,
                      'initial_balance': initial,
                    })
                    .select('id')
                    .single())['id']
                as String;
        final amd = await account('Synthetic AMD', 'AMD', '100');
        final cash = await account('Synthetic cash', 'AMD', '0');
        await account('Synthetic RUB', 'RUB', '-10');
        await client.from('transactions').insert({
          'account_id': amd,
          'category_id': cat,
          'transaction_type': 'expense',
          'transaction_date': '2026-11-02',
          'amount': '5',
          'currency': 'USD',
          'account_amount': '2000',
          'account_currency': 'AMD',
        });
        await client.rpc(
          'create_manual_transfer',
          params: {
            'p_from': amd,
            'p_to': cash,
            'p_date': '2026-11-01',
            'p_from_amount': '10',
            'p_to_amount': '10',
            'p_fee': '0',
            'p_description': 'Synthetic transfer',
            'p_request_id': '86300000-0000-4000-8000-000000000001',
          },
        );
        final report = await SupabasePeriodReportRepository(
          client,
        ).load(DateTime(2026, 11, 1), DateTime(2026, 11, 2), 'AMD');
        final quote = await RateQuoteCache.load(client);
        expect(
          report.balance,
          BigInt.from(-190000) +
              quote.convert(BigInt.from(-1000), 'RUB', 'AMD'),
        );
        expect(report.current.expense, BigInt.from(200000));
        expect(report.current.income, BigInt.zero);
        expect(report.currencies['USD']!.expense, BigInt.from(500));
        expect(report.accounts.length, 3);
      } finally {
        await client.dispose();
        await localSql("delete from auth.users where email = '$email';");
      }
    },
    skip: enabled ? false : 'Requires local Supabase and Edge Runtime',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
