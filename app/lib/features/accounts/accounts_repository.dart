import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.bankId,
    this.bankName,
    this.initialBalance = '0',
    this.currentBalance = '0',
    this.isActive = true,
  });
  final String id;
  final String name;
  final String type;
  final String currency;
  final String? bankId;
  final String? bankName;
  final String initialBalance;
  final String currentBalance;
  final bool isActive;

  factory AccountSummary.fromJson(Map<String, dynamic> json) => AccountSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    type: json['account_type'] as String,
    currency: json['currency'] as String,
    bankId: json['bank_id'] as String?,
    bankName: json['bank_name'] as String?,
    initialBalance: json['initial_balance'] as String,
    currentBalance: json['current_balance'] as String,
    isActive: json['is_active'] as bool,
  );
}

class Bank {
  const Bank({required this.id, required this.name});
  final String id;
  final String name;
}

class AccountInput {
  const AccountInput({
    required this.name,
    required this.type,
    required this.currency,
    required this.initialBalance,
    this.bankId,
  });
  final String name;
  final String type;
  final String currency;
  final String initialBalance;
  final String? bankId;
  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'account_type': type,
    'currency': currency,
    'initial_balance': initialBalance,
    'bank_id': type == 'bank' ? bankId : null,
  };
}

abstract interface class AccountsRepository {
  Future<List<AccountSummary>> loadAccounts();
  Future<List<Bank>> loadBanks();
  Future<void> createAccount(AccountInput input);
  Future<void> updateAccount(String id, AccountInput input);
  Future<void> setActive(String id, bool active);
}

class SupabaseAccountsRepository implements AccountsRepository {
  SupabaseAccountsRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<AccountSummary>> loadAccounts() async {
    final rows = await client
        .from('account_balances')
        .select()
        .order('created_at')
        .order('id');
    return rows.map(AccountSummary.fromJson).toList(growable: false);
  }

  @override
  Future<List<Bank>> loadBanks() async {
    final rows = await client.from('banks').select('id,name').order('name');
    return rows
        .map(
          (row) => Bank(id: row['id'] as String, name: row['name'] as String),
        )
        .toList(growable: false);
  }

  @override
  Future<void> createAccount(AccountInput input) async {
    await client.from('accounts').insert(input.toJson());
  }

  @override
  Future<void> updateAccount(String id, AccountInput input) async {
    await client
        .from('accounts')
        .update(input.toJson())
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<void> setActive(String id, bool active) async {
    await client
        .from('accounts')
        .update({'is_active': active})
        .eq('id', id)
        .select('id')
        .single();
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
final banksProvider = FutureProvider.autoDispose<List<Bank>>(
  (ref) => ref.watch(accountsRepositoryProvider).loadBanks(),
  dependencies: [accountsRepositoryProvider],
  retry: (_, _) => null,
);
