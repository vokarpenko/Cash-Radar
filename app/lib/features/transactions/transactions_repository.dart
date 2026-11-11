import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionEntry {
  const TransactionEntry({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.accountActive,
    required this.categoryId,
    required this.categoryName,
    required this.type,
    required this.date,
    required this.amount,
    required this.currency,
    required this.accountAmount,
    required this.accountCurrency,
    this.description,
  });
  final String id,
      accountId,
      accountName,
      categoryId,
      categoryName,
      type,
      date,
      amount,
      currency,
      accountAmount,
      accountCurrency;
  final bool accountActive;
  final String? description;

  factory TransactionEntry.fromJson(Map<String, dynamic> row) =>
      TransactionEntry(
        id: row['id'] as String,
        accountId: row['account_id'] as String,
        accountName: row['account_name'] as String,
        accountActive: row['account_active'] as bool,
        categoryId: row['category_id'] as String,
        categoryName: row['category_name'] as String,
        type: row['transaction_type'] as String,
        date: row['transaction_date'] as String,
        amount: row['amount'] as String,
        currency: row['currency'] as String,
        accountAmount: row['account_amount'] as String,
        accountCurrency: row['account_currency'] as String,
        description: row['raw_description'] as String?,
      );
}

class TransactionCategory {
  const TransactionCategory({
    required this.id,
    required this.name,
    required this.kind,
  });
  final String id, name, kind;
}

class TransactionInput {
  const TransactionInput({
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.date,
    required this.amount,
    required this.currency,
    required this.accountAmount,
    required this.accountCurrency,
    this.description,
  });
  final String accountId,
      categoryId,
      type,
      date,
      amount,
      currency,
      accountAmount,
      accountCurrency;
  final String? description;
  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'category_id': categoryId,
    'transaction_type': type,
    'transaction_date': date,
    'amount': amount,
    'currency': currency,
    'account_amount': accountAmount,
    'account_currency': accountCurrency,
    'raw_description': description?.trim().isEmpty == true
        ? null
        : description?.trim(),
  };
}

abstract interface class TransactionsRepository {
  Future<List<TransactionEntry>> loadTransactions();
  Future<List<TransactionCategory>> loadCategories();
  Future<void> createTransaction(TransactionInput input);
  Future<void> updateTransaction(String id, TransactionInput input);
  Future<void> deleteTransaction(String id);
}

class SupabaseTransactionsRepository implements TransactionsRepository {
  SupabaseTransactionsRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<TransactionEntry>> loadTransactions() async {
    final rows = await client
        .from('transaction_details')
        .select()
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .order('id');
    return rows.map(TransactionEntry.fromJson).toList(growable: false);
  }

  @override
  Future<List<TransactionCategory>> loadCategories() async {
    final rows = await client
        .from('categories')
        .select('id,name,kind')
        .inFilter('kind', ['income', 'expense'])
        .order('name')
        .order('id');
    return rows
        .map(
          (row) => TransactionCategory(
            id: row['id'] as String,
            name: row['name'] as String,
            kind: row['kind'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> createTransaction(TransactionInput input) async {
    await client.from('transactions').insert(input.toJson());
  }

  @override
  Future<void> updateTransaction(String id, TransactionInput input) async {
    await client
        .from('transactions')
        .update(input.toJson())
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<void> deleteTransaction(String id) async {
    await client
        .from('transactions')
        .delete()
        .eq('id', id)
        .select('id')
        .single();
  }
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => SupabaseTransactionsRepository(Supabase.instance.client),
  dependencies: const [],
);
final transactionsProvider = FutureProvider.autoDispose<List<TransactionEntry>>(
  (ref) => ref.watch(transactionsRepositoryProvider).loadTransactions(),
  dependencies: [transactionsRepositoryProvider],
  retry: (_, _) => null,
);
final transactionCategoriesProvider =
    FutureProvider.autoDispose<List<TransactionCategory>>(
      (ref) => ref.watch(transactionsRepositoryProvider).loadCategories(),
      dependencies: [transactionsRepositoryProvider],
      retry: (_, _) => null,
    );
