#!/usr/bin/env python3
"""Local-only end-to-end import test; removes only its own users and objects."""
import base64
import concurrent.futures
from decimal import Decimal
import hashlib
import json
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[2]
config = json.loads((root / 'app/config/local-supabase.json').read_text())
base = config['SUPABASE_URL']
parsed = urllib.parse.urlparse(base)
if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or parsed.port != 54321:
    raise SystemExit('This test only runs against local Supabase on 127.0.0.1:54321')
key = config['SUPABASE_PUBLISHABLE_KEY']
status = subprocess.run(['npx', '--yes', 'supabase@3', 'status', '--output', 'json'], cwd=root, capture_output=True, text=True, check=True)
admin_key = json.loads(status.stdout)['SERVICE_ROLE_KEY']
suffix = str(time.time_ns())
emails = [f'cashradar_import_{suffix}_{n}@example.test' for n in ('a', 'b')]
if not all(re.fullmatch(r'cashradar_import_\d+_[ab]@example\.test', email) for email in emails):
    raise SystemExit('Unsafe test email')
password = 'local-import-test-pass-123'
users = []
object_paths = set()

def request(path, method='GET', token=None, data=None, raw=None, admin=False):
    headers = {'apikey': admin_key if admin else key}
    if token or admin:
        headers['Authorization'] = 'Bearer ' + (admin_key if admin else token)
    if method == 'POST' and path.startswith('/rest/v1/accounts'):
        headers['Prefer'] = 'return=representation'
    if data is not None:
        raw = json.dumps(data, ensure_ascii=False).encode()
        headers['Content-Type'] = 'application/json'
    elif raw is not None:
        headers['Content-Type'] = 'text/csv'
    req = urllib.request.Request(base + path, data=raw, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=35) as response:
            payload = response.read()
            content_type = response.headers.get('Content-Type', '')
            return response.status, json.loads(payload) if 'application/json' in content_type and payload else payload
    except urllib.error.HTTPError as exc:
        payload = exc.read()
        try:
            body = json.loads(payload)
        except (ValueError, UnicodeDecodeError):
            body = {}
        return exc.code, body

def require(value, message):
    if not value:
        raise AssertionError(message)

def signup(email):
    code, _ = request('/auth/v1/signup', 'POST', data={'email': email, 'password': password})
    require(code in (200, 201), 'Local signup failed')
    subprocess.run(['docker','exec','supabase_db_Cash-Radar','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',f"update auth.users set email_confirmed_at=now() where email='{email}';"], capture_output=True, check=True)
    code, data = request('/auth/v1/token?grant_type=password', 'POST', data={'email':email,'password':password})
    require(code == 200, 'Local login failed')
    return {'id': data['user']['id'], 'token': data['access_token']}

def invoke(user, account, raw, name='statement.csv'):
    object_paths.add(f"{user['id']}/{hashlib.sha256(raw).hexdigest()}.csv")
    return request('/functions/v1/import-statement', 'POST', token=user['token'], data={'account_id':account,'filename':name,'file_base64':base64.b64encode(raw).decode()})

def get(user, path):
    return request(path, token=user['token'])

try:
    users = [signup(email) for email in emails]
    a, b = users
    for user in users:
        code, account = request('/rest/v1/accounts?select=id', 'POST', token=user['token'], data={'name':'Local import wallet','account_type':'cash','currency':'AMD','initial_balance':'100.00'})
        require(code == 201 and len(account) == 1, 'Local account creation failed')
        user['account'] = account[0]['id']
    header = 'date,type,amount,currency,account_amount,category,description\n'
    content = (header + '2026-11-11,expense,10.25,AMD,,Продукты,Local test\n2026-11-12,income,2.00,AMD,,Зарплата,Local test\n').encode()
    code, result = invoke(a, a['account'], content)
    require(code == 200 and result.get('status') == 'ready' and not result.get('duplicate'), f'Import preparation failed ({code}): {result.get("error", "")}')
    batch = result['id']
    code, batches = get(a, f'/rest/v1/import_batches?select=id,status,object_path&id=eq.{batch}')
    require(code == 200 and len(batches) == 1, 'Owner cannot view batch')
    path = batches[0]['object_path']
    require(path in object_paths, 'Unexpected object path')
    code, original = get(a, f'/storage/v1/object/authenticated/statements/{path}')
    require(code == 200 and original == content, 'Owner cannot retrieve exact original')
    code, _ = get(b, f'/storage/v1/object/authenticated/statements/{path}')
    require(code in (400,401,403,404), 'Other user can read private original')
    code, _ = request(f'/storage/v1/object/authenticated/statements/{path}')
    require(code in (400,401,403,404), 'Anonymous user can read private original')
    code, _ = request(f'/storage/v1/object/public/statements/{path}')
    require(code in (400,401,403,404), 'Private bucket is publicly readable')
    code, foreign = get(b, f'/rest/v1/import_item_details?select=id&batch_id=eq.{batch}')
    require(code == 200 and foreign == [], 'Other user can read preview')
    code, _ = request('/rest/v1/rpc/confirm_statement_import', 'POST', token=b['token'], data={'p_batch_id':batch})
    require(code >= 400, 'Other user could confirm import')
    code, _ = request('/rest/v1/rpc/register_statement_import', 'POST', token=a['token'], data={})
    require(code >= 400, 'Client could access trusted registration')
    evil = f"{a['id']}/test-direct-upload.csv"
    object_paths.add(evil)
    code, _ = request(f'/storage/v1/object/statements/{evil}', 'POST', token=a['token'], raw=b'not allowed')
    require(code >= 400, 'Client could write directly to original storage')
    def confirm():
        return request('/rest/v1/rpc/confirm_statement_import', 'POST', token=a['token'], data={'p_batch_id':batch})
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda _: confirm(), range(4)))
    require(all(code == 200 and data.get('imported_count') == 2 for code, data in results), 'Concurrent confirmation failed')
    require(sum(not data.get('already_confirmed') for _, data in results) == 1, 'Concurrent confirmation duplicated data')
    code, data = get(a, f'/rest/v1/transaction_details?select=id&account_id=eq.{a["account"]}')
    require(code == 200 and len(data) == 2, 'Wrong transaction count after confirmation')
    code, data = get(a, f'/rest/v1/account_balances?select=current_balance&id=eq.{a["account"]}')
    require(code == 200 and Decimal(data[0]['current_balance']) == Decimal('91.75'), 'Wrong resulting balance')
    code, repeat = invoke(a, a['account'], content, 'different-name.csv')
    require(code == 200 and repeat.get('duplicate') and repeat.get('id') == batch, 'Duplicate file not detected')
    bad = (header+'2026-11-11,expense,1.234,AMD,,Продукты,Local test\n').encode()
    code, invalid = invoke(a, a['account'], bad)
    require(code == 200 and invalid.get('status') == 'invalid', 'Invalid row not reported')
    code, invalid_batch = get(a, f'/rest/v1/import_batches?select=error_count,errors&id=eq.{invalid["id"]}')
    require(code == 200 and invalid_batch[0]['error_count'] == 1, 'Error report missing')
    code, _ = request('/rest/v1/rpc/confirm_statement_import', 'POST', token=a['token'], data={'p_batch_id':invalid['id']})
    require(code >= 400, 'Invalid import could be confirmed')
    code, retry = invoke(a, a['account'], bad)
    require(code == 200 and retry.get('status') == 'invalid' and retry.get('id') != invalid['id'], 'Invalid file could not be retried')
    code, _ = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=b['token'], data={'p_batch_id':retry['id']})
    require(code >= 400, 'Other user could cancel import')
    code, cancelled = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=a['token'], data={'p_batch_id':retry['id']})
    require(code == 200 and not cancelled.get('already_cancelled'), 'Could not cancel invalid import')
    code, _ = request('/rest/v1/rpc/confirm_statement_import', 'POST', token=a['token'], data={'p_batch_id':retry['id']})
    require(code >= 400, 'Cancelled import could be confirmed')
    code, _ = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=a['token'], data={'p_batch_id':batch})
    require(code >= 400, 'Completed import could be cancelled')

    code, euro_account = request('/rest/v1/accounts?select=id', 'POST', token=a['token'], data={'name':'Euro fixture','account_type':'cash','currency':'EUR','initial_balance':'0.00'})
    require(code == 201, 'Could not create second account')
    mismatched = (header+'2026-11-08,expense,4.00,EUR,,Продукты,Currency retry\n').encode()
    code, bad_account = invoke(a, a['account'], mismatched)
    require(code == 200 and bad_account.get('status') == 'invalid', 'Missing account amount was accepted')
    code, fixed_account = invoke(a, euro_account[0]['id'], mismatched)
    require(code == 200 and fixed_account.get('status') == 'ready' and not fixed_account.get('duplicate'), 'Retry with correct account failed')
    code, _ = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=a['token'], data={'p_batch_id':fixed_account['id']})
    require(code == 200, 'Could not cancel second-account fixture')
    parallel = (header+'2026-11-09,income,4.00,AMD,,Зарплата,Parallel upload\n').encode()
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        uploads = list(pool.map(lambda _: invoke(a, a['account'], parallel), range(4)))
    require(all(code == 200 for code, _ in uploads), 'Concurrent file preparation failed')
    require(len({data['id'] for _, data in uploads}) == 1, 'Concurrent upload created duplicate batches')
    require(sum(not data['duplicate'] for _, data in uploads) == 1, 'Concurrent upload did not identify one original')
    code, _ = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=a['token'], data={'p_batch_id':uploads[0][1]['id']})
    require(code == 200, 'Could not cancel parallel upload fixture')
    code, _ = invoke(a, a['account'], b'x' * (1024 * 1024 + 1))
    require(code == 413, 'Oversized file was accepted')
    pending = (header+'2026-11-10,income,3.00,AMD,,Зарплата,Pending cancel\n').encode()
    code, pending_result = invoke(a, a['account'], pending)
    require(code == 200 and pending_result.get('status') == 'ready', 'Could not stage cancellable import')
    code, _ = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=a['token'], data={'p_batch_id':pending_result['id']})
    require(code == 200, 'Could not cancel ready import')
    code, pending_retry = invoke(a, a['account'], pending)
    require(code == 200 and pending_retry.get('status') == 'ready' and not pending_retry.get('duplicate') and pending_retry.get('id') != pending_result['id'], 'Cancelled file could not be reprocessed')
    code, _ = request('/rest/v1/rpc/cancel_statement_import', 'POST', token=a['token'], data={'p_batch_id':pending_retry['id']})
    require(code == 200, 'Could not clean up prepared import')
    code, _ = invoke(a, b['account'], content+b'\n')
    require(code >= 400, 'Other user account accepted')
    code, _ = invoke(a, a['account'], b'%PDF-1.7 example')
    require(code == 422, 'Unsupported PDF not detected')
    code, _ = invoke(a, a['account'], b'PK\x03\x04 example')
    require(code == 422, 'Unsupported XLSX/ZIP not detected')
    code, _ = request('/functions/v1/import-statement', 'POST', data={'account_id':a['account'],'file_base64':''})
    require(code in (401,403), 'Unauthenticated import allowed')
    print('Local import: upload, exact original, private storage, RLS, validation, duplicate and concurrent confirmation passed.')
finally:
    if object_paths:
        code, _ = request('/storage/v1/object/statements', 'DELETE', admin=True, data={'prefixes':sorted(object_paths)})
        if code not in (200, 204):
            print('Test object cleanup did not complete; paths belong only to test users.')
    subprocess.run(['docker','exec','supabase_db_Cash-Radar','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',"delete from auth.users where email in ("+','.join("'"+e+"'" for e in emails)+");"], capture_output=True, check=True)
