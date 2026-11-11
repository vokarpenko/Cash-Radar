import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class CurrencyRepository {
  Future<String> loadBaseCurrency();
  Future<void> saveBaseCurrency(String currency);
}

class SupabaseCurrencyRepository implements CurrencyRepository {
  SupabaseCurrencyRepository(this.client);
  final SupabaseClient client;
  String get userId =>
      client.auth.currentUser?.id ?? (throw StateError('No active user'));

  @override
  Future<String> loadBaseCurrency() async {
    final row = await client
        .from('profiles')
        .select('base_currency')
        .eq('id', userId)
        .single();
    return row['base_currency'] as String;
  }

  @override
  Future<void> saveBaseCurrency(String currency) async {
    await client
        .from('profiles')
        .update({'base_currency': currency})
        .eq('id', userId)
        .select('id')
        .single();
  }
}

final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => SupabaseCurrencyRepository(Supabase.instance.client),
  dependencies: const [],
);
final baseCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(currencyRepositoryProvider).loadBaseCurrency(),
  dependencies: [currencyRepositoryProvider],
  retry: (_, _) => null,
);
