#!/usr/bin/env python3
"""Local-only AI integration test. Sends one fictional name, no financial data, to Gemini."""
import json
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
    raise SystemExit('Refusing to run outside local Supabase')
pub = config['SUPABASE_PUBLISHABLE_KEY']
cmd = ['npx', '--yes', 'supabase@3']
admin = json.loads(subprocess.run(cmd + ['status', '--output', 'json'], cwd=root, capture_output=True, text=True, check=True).stdout)['SERVICE_ROLE_KEY']

def request(path, method='GET', payload=None, token=None, service=False):
    headers = {'apikey': admin if service else pub}
    if token or service: headers['Authorization'] = 'Bearer ' + (admin if service else token)
    headers['Content-Type'] = 'application/json'
    headers['Prefer'] = 'return=representation'
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            body = resp.read()
            return resp.status, json.loads(body) if body else None
    except urllib.error.HTTPError as exc:
        body = exc.read()
        try: body = json.loads(body)
        except ValueError: body = None
        return exc.code, body

def require(condition, message):
    if not condition: raise AssertionError(message)

user = None
try:
    suffix = str(time.time_ns())
    email = f'cashradar_ai_{suffix}@example.test'
    password = 'Local-AI-Example-123!'
    code, info = request('/auth/v1/admin/users', 'POST', {'email':email,'password':password,'email_confirm':True}, service=True)
    require(code in (200, 201) and info.get('id'), 'Could not create synthetic user')
    user = info['id']
    code, info = request('/auth/v1/token?grant_type=password', 'POST', {'email':email,'password':password})
    require(code == 200, 'Could not sign in synthetic user')
    token = info['access_token']
    code, banks = request('/rest/v1/banks?code=eq.acba_am&select=id', token=token)
    require(code == 200 and len(banks)==1, 'Missing local bank')
    code, accounts = request('/rest/v1/accounts?select=id', 'POST', {'name':'Synthetic account','account_type':'bank','bank_id':banks[0]['id'],'currency':'AMD','initial_balance':'0'}, token=token)
    require(code == 201 and len(accounts)==1, 'Could not create local account')
    account = accounts[0]['id']
    code, categories = request('/rest/v1/categories?name=eq.' + urllib.parse.quote('Прочие расходы') + '&select=id', token=token)
    require(code == 200 and len(categories)==1, 'Missing default category')
    row = {'row_number':2,'transaction_date':'2026-11-01','transaction_type':'expense','amount':'10','currency':'AMD','account_amount':'10','category_id':categories[0]['id'],'raw_description':'Imaginary Example Grocer','raw_data':{}}
    code, result = request('/rest/v1/rpc/register_statement_import', 'POST', {'p_user_id':user,'p_account_id':account,'p_currency':'AMD','p_filename':'synthetic.xlsx','p_sha256':('a'+suffix.zfill(63))[-64:],'p_items':[row],'p_errors':[],'p_error_count':0,'p_format':'acba_xlsx_v1'}, service=True)
    require(code == 200 and result.get('id'), 'Could not create local synthetic import')
    batch = result['id']
    code, groups = request('/rest/v1/rpc/ai_import_candidates','POST',{'p_batch_id':batch},token=token)
    require(code == 200 and len(groups)==1, 'Candidate grouping failed')
    selected = {'group_id':groups[0]['group_id'],'merchant':groups[0]['merchant']}
    code, _ = request('/functions/v1/categorize-merchant','POST',{'batch_id':batch,'groups':[selected]})
    require(code == 401, 'Unauthenticated request was accepted')
    code, _ = request('/functions/v1/categorize-merchant','POST',{'batch_id':batch,'groups':[dict(selected, merchant='Different imaginary merchant')]},token=token)
    require(code == 409, 'Changed preview name was accepted')
    code, result = request('/functions/v1/categorize-merchant','POST',{'batch_id':batch,'groups':[selected]},token=token)
    require(code == 200 and isinstance(result.get('rules'),int) and isinstance(result.get('suggestions'),int) and isinstance(result.get('unrecognized'),int) and result.get('model') in ('gemini-4-hydrogen','gemini-3.8-flash'), f'Synthetic AI request failed: HTTP {code}, {result.get("error", "unknown") if isinstance(result, dict) else "unknown"}')
    if result['rules'] or result['suggestions'] or result['unrecognized']:
        code, _ = request('/functions/v1/categorize-merchant','POST',{'batch_id':batch,'groups':[selected]},token=token)
        require(code == 409, 'Known merchant was eligible for another request')
    print('Local AI end-to-end test passed; only a fictional name was sent to Gemini.')
finally:
    if user:
        for table in ('ai_suggestions','ai_merchant_rules','import_items','import_batches','accounts'):
            request(f'/rest/v1/{table}?user_id=eq.{user}', 'DELETE', service=True)
        request('/auth/v1/admin/users/' + user, 'DELETE', service=True)
