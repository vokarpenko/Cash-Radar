import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/auth/auth_service.dart';
import 'package:cash_radar/features/settings/currency_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/local_supabase.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_LOCAL_FOUNDATION_TESTS');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  test(
    'real users can only access their own foundation data',
    () async {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          uri.port != 54321) {
        throw StateError(
          'This test is restricted to local Supabase at 127.0.0.1:54321',
        );
      }
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final emailA = 'cashradar_stage3_a_$suffix@example.test';
      final emailB = 'cashradar_stage3_b_$suffix@example.test';
      const password = 'temporary-pass-123';
      final clientA = SupabaseClient(
        url,
        key,
        authOptions: AuthClientOptions(
          pkceAsyncStorage: MemoryVerifierStorage(),
        ),
      );
      final clientB = SupabaseClient(
        url,
        key,
        authOptions: AuthClientOptions(
          pkceAsyncStorage: MemoryVerifierStorage(),
        ),
      );
      final authA = SupabaseAuthService(clientA);
      final authB = SupabaseAuthService(clientB);
      try {
        expect(await authA.signUp(emailA, password), isFalse);
        await followLocalMailLink(clientA, await readLocalMailLink(emailA));
        final userA = clientA.auth.currentUser!.id;
        expect(await authB.signUp(emailB, password), isFalse);
        await followLocalMailLink(clientB, await readLocalMailLink(emailB));
        final userB = clientB.auth.currentUser!.id;
        expect(userA, isNot(userB));

        final profilesA = await clientA.from('profiles').select('id');
        final profilesB = await clientB.from('profiles').select('id');
        expect(profilesA.map((row) => row['id']), [userA]);
        expect(profilesB.map((row) => row['id']), [userB]);
        expect(await clientA.from('banks').select('code'), hasLength(3));
        final categoriesA = await clientA
            .from('categories')
            .select('id, user_id');
        final categoriesB = await clientB
            .from('categories')
            .select('id, user_id');
        expect(categoriesA, hasLength(16));
        expect(categoriesB, hasLength(16));
        expect(categoriesA.every((row) => row['user_id'] == userA), isTrue);
        expect(categoriesB.every((row) => row['user_id'] == userB), isTrue);

        final currencyA = SupabaseCurrencyRepository(clientA);
        final currencyB = SupabaseCurrencyRepository(clientB);
        expect(await currencyA.loadBaseCurrency(), 'AMD');
        await currencyA.saveBaseCurrency('EUR');
        expect(await currencyA.loadBaseCurrency(), 'EUR');
        expect(await currencyB.loadBaseCurrency(), 'AMD');
        expect(
          await clientB
              .from('profiles')
              .update({'base_currency': 'RUB'})
              .eq('id', userA)
              .select('id'),
          isEmpty,
        );
        await expectLater(
          clientA
              .from('profiles')
              .update({'base_currency': 'invalid'})
              .eq('id', userA),
          throwsA(isA<PostgrestException>()),
        );
        final repoA = SupabaseAccountsRepository(clientA);
        await repoA.createAccount(
          const AccountInput(
            name: 'Exact wallet',
            type: 'cash',
            currency: 'USD',
            initialBalance: '999999999999999999.99',
          ),
        );
        var exact = (await repoA.loadAccounts()).singleWhere(
          (a) => a.name == 'Exact wallet',
        );
        expect(exact.initialBalance, '999999999999999999.99');
        expect(exact.currentBalance, '999999999999999999.99');
        expect(
          await clientB
              .from('account_balances')
              .select('id')
              .eq('id', exact.id),
          isEmpty,
        );
        await expectLater(
          SupabaseAccountsRepository(clientB).setActive(exact.id, false),
          throwsA(anything),
        );
        await repoA.updateAccount(
          exact.id,
          const AccountInput(
            name: 'Edited wallet',
            type: 'cash',
            currency: 'EUR',
            initialBalance: '-0.01',
          ),
        );
        exact = (await repoA.loadAccounts()).singleWhere(
          (a) => a.id == exact.id,
        );
        expect(exact.name, 'Edited wallet');
        expect(exact.currentBalance, '-0.01');
        expect(exact.currency, 'EUR');
        await repoA.setActive(exact.id, false);
        expect(
          (await repoA.loadAccounts())
              .singleWhere((a) => a.id == exact.id)
              .isActive,
          isFalse,
        );
        await repoA.setActive(exact.id, true);
        expect(
          (await repoA.loadAccounts())
              .singleWhere((a) => a.id == exact.id)
              .isActive,
          isTrue,
        );

        final accountA = await clientA
            .from('accounts')
            .insert({
              'name': 'Wallet A',
              'account_type': 'cash',
              'currency': 'AMD',
              'initial_balance': '123.45',
            })
            .select('id, user_id, initial_balance')
            .single();
        final accountB = await clientB
            .from('accounts')
            .insert({
              'name': 'Wallet B',
              'account_type': 'cash',
              'currency': 'RUB',
              'initial_balance': '-5.25',
            })
            .select('id, user_id')
            .single();
        expect(accountA['user_id'], userA);
        expect(accountB['user_id'], userB);
        final bank = await clientA
            .from('banks')
            .select('id, name')
            .eq('code', 'ameria_am')
            .single();
        await clientA.from('accounts').insert({
          'name': 'Ameria card',
          'account_type': 'bank',
          'bank_id': bank['id'],
          'currency': 'AMD',
        });
        await clientA.from('accounts').insert({
          'name': 'Archived wallet',
          'account_type': 'cash',
          'currency': 'EUR',
          'is_active': false,
        });
        final visibleAccounts = await SupabaseAccountsRepository(
          clientA,
        ).loadAccounts();
        expect(visibleAccounts.map((account) => account.name).toSet(), {
          'Wallet A',
          'Ameria card',
          'Archived wallet',
          'Edited wallet',
        });
        expect(
          visibleAccounts
              .singleWhere((account) => account.name == 'Ameria card')
              .bankName,
          bank['name'],
        );
        expect(
          await clientA.from('accounts').select('id').eq('id', accountB['id']),
          isEmpty,
        );
        expect(
          await clientB.from('accounts').select('id').eq('id', accountA['id']),
          isEmpty,
        );
        expect(
          await clientA
              .from('accounts')
              .update({'name': 'Other'})
              .eq('id', accountB['id'])
              .select('id'),
          isEmpty,
        );
        await expectLater(
          clientA.from('accounts').insert({
            'user_id': userB,
            'name': 'Spoofed',
            'account_type': 'cash',
            'currency': 'AMD',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          clientA.from('accounts').insert({
            'name': 'Too precise',
            'account_type': 'cash',
            'currency': 'AMD',
            'initial_balance': '0.001',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          clientA.from('categories').insert({
            'name': 'Foreign parent',
            'kind': 'expense',
            'parent_id': categoriesB.first['id'],
          }),
          throwsA(isA<PostgrestException>()),
        );
        final child = await clientA
            .from('categories')
            .insert({
              'name': 'Child',
              'kind': 'expense',
              'parent_id': categoriesA.first['id'],
            })
            .select('id')
            .single();
        await expectLater(
          clientA
              .from('categories')
              .update({'parent_id': child['id']})
              .eq('id', categoriesA.first['id']),
          throwsA(isA<PostgrestException>()),
        );
        expect(await clientB.from('categories').select('id'), hasLength(16));
        await expectLater(
          clientA.from('banks').insert({'code': 'unauthorized', 'name': 'Bad'}),
          throwsA(isA<PostgrestException>()),
        );

        final anonymous = SupabaseClient(url, key);
        try {
          await expectLater(
            anonymous.from('profiles').select(),
            throwsA(isA<PostgrestException>()),
          );
          await expectLater(
            anonymous.from('accounts').select(),
            throwsA(isA<PostgrestException>()),
          );
          await expectLater(
            anonymous.from('account_balances').select(),
            throwsA(isA<PostgrestException>()),
          );
          await expectLater(
            anonymous.from('categories').select(),
            throwsA(isA<PostgrestException>()),
          );
          await expectLater(
            anonymous.from('banks').select(),
            throwsA(isA<PostgrestException>()),
          );
        } finally {
          await anonymous.dispose();
        }
      } finally {
        await clientA.dispose();
        await clientB.dispose();
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
