import 'package:cash_radar/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/local_supabase.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_LOCAL_AUTH_TESTS');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  test(
    'local registration, confirmation, recovery and user isolation',
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
      final table = 'stage2_auth_probe_$suffix';
      final emailA = 'cashradar_a_$suffix@example.test';
      final emailB = 'cashradar_b_$suffix@example.test';
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
      var tableCreated = false;
      try {
        expect(await authA.signUp(emailA, password), isFalse);
        await expectLater(
          authA.signIn(emailA, password),
          throwsA(isA<AuthException>()),
        );
        await followLocalMailLink(clientA, await readLocalMailLink(emailA));
        final idA = clientA.auth.currentUser!.id;
        await authA.signOut();
        await authA.signIn(emailA, password);
        expect(authA.hasSession, isTrue);

        expect(await authB.signUp(emailB, password), isFalse);
        await followLocalMailLink(clientB, await readLocalMailLink(emailB));
        final idB = clientB.auth.currentUser!.id;
        expect(idA, isNot(idB));

        await localSql(
          'create table public.$table (id text primary key, owner uuid not null, note text); '
          'alter table public.$table enable row level security; '
          'grant select, insert, update, delete on public.$table to authenticated; '
          'create policy owner_only on public.$table for all to authenticated '
          'using (owner = (select auth.uid())) with check (owner = (select auth.uid())); '
          "notify pgrst, 'reload schema';",
        );
        tableCreated = true;
        await Future<void>.delayed(const Duration(seconds: 1));
        await clientA.from(table).insert({
          'id': 'a',
          'owner': idA,
          'note': 'first',
        });
        await clientB.from(table).insert({
          'id': 'b',
          'owner': idB,
          'note': 'second',
        });
        final rowsA = await clientA.from(table).select('id');
        final rowsB = await clientB.from(table).select('id');
        expect(rowsA.map((r) => r['id']), ['a']);
        expect(rowsB.map((r) => r['id']), ['b']);
        await expectLater(
          clientA.from(table).insert({'id': 'forged', 'owner': idB}),
          throwsA(isA<PostgrestException>()),
        );

        await authA.resetPassword(emailA);
        await followLocalMailLink(clientA, await readLocalMailLink(emailA));
        await authA.updatePassword('new-password-123');
        await authA.signOut();
        await authA.signIn(emailA, 'new-password-123');
        expect(authA.hasSession, isTrue);
        await authA.signOut();
        expect(authA.hasSession, isFalse);
      } finally {
        await clientA.dispose();
        await clientB.dispose();
        if (tableCreated) {
          await localSql(
            "drop table public.$table; notify pgrst, 'reload schema';",
          );
        }
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
