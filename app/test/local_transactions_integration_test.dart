import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/auth/auth_service.dart';
import 'package:cash_radar/features/transactions/transactions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/local_supabase.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_LOCAL_TRANSACTIONS_TESTS');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  test(
    'exact balances, currency integrity and user isolation through real API',
    () async {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          uri.port != 54321) {
        throw StateError('Only local Supabase is permitted');
      }
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final emailA = 'cashradar_stage6_a_$suffix@example.test';
      final emailB = 'cashradar_stage6_b_$suffix@example.test';
      const password = 'temporary-pass-123';
      SupabaseClient createClient() => SupabaseClient(
        url,
        key,
        authOptions: AuthClientOptions(
          pkceAsyncStorage: MemoryVerifierStorage(),
        ),
      );
      final a = createClient(), b = createClient(), anonymous = createClient();
      try {
        final authA = SupabaseAuthService(a), authB = SupabaseAuthService(b);
        expect(await authA.signUp(emailA, password), isFalse);
        await followLocalMailLink(a, await readLocalMailLink(emailA));
        expect(await authB.signUp(emailB, password), isFalse);
        await followLocalMailLink(b, await readLocalMailLink(emailB));
        final userB = b.auth.currentUser!.id;
        final accountA = await a
            .from('accounts')
            .insert({
              'name': 'A wallet',
              'account_type': 'cash',
              'currency': 'AMD',
              'initial_balance': '1000.0000',
            })
            .select('id')
            .single();
        final accountB = await b
            .from('accounts')
            .insert({
              'name': 'B wallet',
              'account_type': 'cash',
              'currency': 'USD',
              'initial_balance': '10',
            })
            .select('id')
            .single();
        final categoryAIncome =
            (await a
                    .from('categories')
                    .select('id')
                    .eq('kind', 'income')
                    .limit(1)
                    .single())['id']
                as String;
        final categoryAExpense =
            (await a
                    .from('categories')
                    .select('id')
                    .eq('kind', 'expense')
                    .limit(1)
                    .single())['id']
                as String;
        final categoryBExpense =
            (await b
                    .from('categories')
                    .select('id')
                    .eq('kind', 'expense')
                    .limit(1)
                    .single())['id']
                as String;
        final repo = SupabaseTransactionsRepository(a);
        final income = TransactionInput(
          accountId: accountA['id'] as String,
          categoryId: categoryAIncome,
          type: 'income',
          date: '2026-11-11',
          amount: '2.0001',
          currency: 'AMD',
          accountAmount: '2.0001',
          accountCurrency: 'AMD',
          description: 'Salary',
        );
        await repo.createTransaction(income);
        var balance = (await SupabaseAccountsRepository(
          a,
        ).loadAccounts()).single;
        expect(balance.currentBalance, '1002.0001');
        expect(balance.hasTransactions, isTrue);
        await repo.createTransaction(
          TransactionInput(
            accountId: accountA['id'] as String,
            categoryId: categoryAExpense,
            type: 'expense',
            date: '2026-11-10',
            amount: '1.25',
            currency: 'EUR',
            accountAmount: '500.0001',
            accountCurrency: 'AMD',
            description: 'Purchase',
          ),
        );
        var txs = await repo.loadTransactions();
        expect(txs, hasLength(2));
        final expense = txs.singleWhere((t) => t.type == 'expense');
        expect(expense.amount, '1.25');
        expect(expense.accountAmount, '500.0001');
        expect(
          (await SupabaseAccountsRepository(
            a,
          ).loadAccounts()).single.currentBalance,
          '502.0000',
        );
        await repo.updateTransaction(
          expense.id,
          TransactionInput(
            accountId: expense.accountId,
            categoryId: expense.categoryId,
            type: 'expense',
            date: '2026-11-09',
            amount: '1.25',
            currency: 'EUR',
            accountAmount: '400.0000',
            accountCurrency: 'AMD',
            description: 'Edited',
          ),
        );
        expect(
          (await SupabaseAccountsRepository(
            a,
          ).loadAccounts()).single.currentBalance,
          '602.0001',
        );
        expect(
          await b.from('transaction_details').select('id').eq('id', expense.id),
          isEmpty,
        );
        expect(
          await b
              .from('transactions')
              .update({'raw_description': 'foreign'})
              .eq('id', expense.id)
              .select('id'),
          isEmpty,
        );
        expect(
          await b
              .from('transactions')
              .delete()
              .eq('id', expense.id)
              .select('id'),
          isEmpty,
        );
        expect(
          await b
              .from('account_balances')
              .select('id')
              .eq('id', accountA['id']),
          isEmpty,
        );
        await expectLater(
          a.from('transactions').insert({...income.toJson(), 'user_id': userB}),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a.from('transactions').insert({
            ...income.toJson(),
            'account_id': accountB['id'],
            'account_currency': 'USD',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a.from('transactions').insert({
            ...income.toJson(),
            'category_id': categoryBExpense,
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a.from('transactions').insert({
            ...income.toJson(),
            'category_id': categoryAExpense,
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a.from('transactions').insert({
            ...income.toJson(),
            'account_currency': 'USD',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a.from('transactions').insert({
            ...income.toJson(),
            'account_amount': '3',
          }),
          throwsA(isA<PostgrestException>()),
        );
        for (final invalid in ['0', '-1', '0.00001', '1000000000000000000']) {
          await expectLater(
            a.from('transactions').insert({
              ...income.toJson(),
              'amount': invalid,
              'account_amount': invalid,
            }),
            throwsA(isA<PostgrestException>()),
          );
        }
        await expectLater(
          a.from('transactions').insert({
            ...income.toJson(),
            'transaction_date': 'infinity',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a
              .from('accounts')
              .update({'currency': 'USD'})
              .eq('id', accountA['id']),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a
              .from('categories')
              .update({'kind': 'expense'})
              .eq('id', categoryAIncome),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          anonymous.from('transactions').select(),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          anonymous.from('transaction_details').select(),
          throwsA(isA<PostgrestException>()),
        );
        await repo.deleteTransaction(expense.id);
        expect(
          (await SupabaseAccountsRepository(
            a,
          ).loadAccounts()).single.currentBalance,
          '1002.0001',
        );
        txs = await repo.loadTransactions();
        await repo.deleteTransaction(txs.single.id);
        balance = (await SupabaseAccountsRepository(a).loadAccounts()).single;
        expect(balance.currentBalance, '1000.0000');
        expect(balance.hasTransactions, isFalse);
        await a
            .from('accounts')
            .update({'currency': 'USD'})
            .eq('id', accountA['id']);
        final large = await a
            .from('accounts')
            .insert({
              'name': 'Big',
              'account_type': 'cash',
              'currency': 'AMD',
              'initial_balance': '999999999999999999.9999',
            })
            .select('id')
            .single();
        await repo.createTransaction(
          TransactionInput(
            accountId: large['id'] as String,
            categoryId: categoryAIncome,
            type: 'income',
            date: '2026-11-11',
            amount: '0.0001',
            currency: 'AMD',
            accountAmount: '0.0001',
            accountCurrency: 'AMD',
          ),
        );
        expect(
          (await SupabaseAccountsRepository(a).loadAccounts())
              .singleWhere((x) => x.id == large['id'])
              .currentBalance,
          '1000000000000000000.0000',
        );
      } finally {
        await a.dispose();
        await b.dispose();
        await anonymous.dispose();
        await localSql(
          "delete from auth.users where email in ('$emailA', '$emailB');",
        );
      }
    },
    skip: enabled
        ? false
        : 'Requires explicitly enabled local Supabase integration test',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
