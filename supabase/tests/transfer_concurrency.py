#!/usr/bin/env python3
"""Local-only concurrency check. Creates and removes one synthetic user."""
import concurrent.futures
import subprocess
import threading
import uuid

user, account_a, account_b, request_id = (str(uuid.uuid4()) for _ in range(4))
base = ['docker', 'exec', '-i', 'supabase_db_Cash-Radar', 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-A', '-t', '-q']

def sql(text):
    result = subprocess.run(base, input=text, text=True, capture_output=True, check=True)
    return result.stdout.strip()

try:
    sql(f"""
      insert into auth.users(id,email,aud,role) values('{user}','cash-transfer-{user}@example.test','authenticated','authenticated');
      insert into public.accounts(id,user_id,name,account_type,currency,initial_balance) values
       ('{account_a}','{user}','Synthetic A','cash','AMD',1000),
       ('{account_b}','{user}','Synthetic B','cash','AMD',0);
    """)
    barrier = threading.Barrier(2)
    def attempt():
        barrier.wait(timeout=10)
        return sql(f"""
          select set_config('request.jwt.claims','{{"sub":"{user}","role":"authenticated"}}',false);
          select public.create_manual_transfer('{account_a}','{account_b}','2026-11-01',100,100,2,'Synthetic','{request_id}');
        """).splitlines()[-1]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(attempt) for _ in range(2)]
        results = [future.result(timeout=30) for future in futures]
    if results[0] != results[1]:
        raise AssertionError('Concurrent retries returned different groups')
    count = sql(f"select (select count(*) from public.transfer_groups where user_id='{user}')||':'||(select count(*) from public.transactions where user_id='{user}');")
    if count != '1:3':
        raise AssertionError('Concurrent retries duplicated operations')
    print('Concurrent transfer retries created one group and one fee.')
finally:
    sql(f"delete from auth.users where id='{user}' and email='cash-transfer-{user}@example.test';")
