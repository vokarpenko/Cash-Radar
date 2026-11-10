#!/usr/bin/env python3
"""Exercise conflicting category edits in the isolated local Supabase database."""
import json
import subprocess
import time
import uuid

CONTAINER = 'supabase_db_Cash-Radar'
BASE = ['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-q', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
user_id, first_id, second_id = (str(uuid.uuid4()) for _ in range(3))
email = f'stage3-concurrency-{user_id}@example.test'


def run_sql(sql):
    result = subprocess.run(BASE, input=sql, capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise RuntimeError('Local SQL failed: ' + result.stderr.strip())
    return result.stdout


def edit_sql(isolation, child, parent, wait):
    claims = json.dumps({'sub': user_id, 'role': 'authenticated'})
    return f"""
      begin isolation level {isolation};
      select set_config('request.jwt.claims', '{claims}', true);
      set local role authenticated;
      update public.categories set parent_id = '{parent}' where id = '{child}';
      select pg_sleep({wait});
      commit;
    """


try:
    run_sql(f"""
      insert into auth.users (id, email, aud, role)
        values ('{user_id}', '{email}', 'authenticated', 'authenticated');
      insert into public.categories (id, user_id, name, kind) values
        ('{first_id}', '{user_id}', 'Concurrency A', 'expense'),
        ('{second_id}', '{user_id}', 'Concurrency B', 'expense');
    """)
    for isolation in ('read committed', 'repeatable read'):
        run_sql(f"update public.categories set parent_id = null where id in ('{first_id}', '{second_id}');")
        first = subprocess.Popen(BASE, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        second = None
        try:
            first.stdin.write(edit_sql(isolation, first_id, second_id, 1.5))
            first.stdin.close()
            first.stdin = None
            time.sleep(0.3)
            second = subprocess.Popen(BASE, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            second.stdin.write(edit_sql(isolation, second_id, first_id, 0))
            second.stdin.close()
            second.stdin = None
            _, first_error = first.communicate(timeout=20)
            _, second_error = second.communicate(timeout=20)
            if (first.returncode == 0) == (second.returncode == 0):
                raise AssertionError(f'{isolation}: expected exactly one successful transaction')
            error = (first_error + second_error).lower()
            if not any(reason in error for reason in ('cycle', 'could not serialize', 'deadlock detected')):
                raise AssertionError(f'{isolation}: unexpected transaction failure: {error}')
        finally:
            for process in (first, second):
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()
        output = run_sql(f"""
          do $$ begin
            if (select count(*) from public.categories
                where (id = '{first_id}' and parent_id = '{second_id}')
                   or (id = '{second_id}' and parent_id = '{first_id}')) <> 1 then
              raise exception 'Expected exactly one parent link';
            end if;
          end $$;
        """)
        print(f'{isolation}: concurrent cycle prevented')
finally:
    run_sql(f"delete from auth.users where id = '{user_id}';")
