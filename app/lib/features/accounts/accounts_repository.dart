import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.bankName,
  });
  final String id;
  final String name;
  final String type;
  final String currency;
  final String? bankName;

  factory AccountSummary.fromJson(Map<String, dynamic> json) {
    final bank = json['banks'];
    return AccountSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['account_type'] as String,
      currency: json['currency'] as String,
      bankName: bank is Map ? bank['name'] as String? : null,
    );
  }
}

abstract interface class AccountsRepository {
  Future<List<AccountSummary>> loadAccounts();
}

class SupabaseAccountsRepository implements AccountsRepository {
  SupabaseAccountsRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<AccountSummary>> loadAccounts() async {
    final rows = await client
        .from('accounts')
        .select('id,name,account_type,currency,banks(name)')
        .eq('is_active', true)
        .order('created_at')
        .order('id');
    return rows.map(AccountSummary.fromJson).toList(growable: false);
  }
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => SupabaseAccountsRepository(Supabase.instance.client),
  dependencies: const [],
);

final accountsProvider = FutureProvider.autoDispose<List<AccountSummary>>(
  (ref) => ref.watch(accountsRepositoryProvider).loadAccounts(),
  dependencies: [accountsRepositoryProvider],
  retry: (_, _) => null,
);
