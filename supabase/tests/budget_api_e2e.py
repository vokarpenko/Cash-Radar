#!/usr/bin/env python3
"""Local-only API test with a temporary synthetic account. Never prints credentials."""
import json, shutil, subprocess, time, urllib.error, urllib.request
from pathlib import Path
root = Path(__file__).resolve().parents[2]
cli = [shutil.which('supabase')] if shutil.which('supabase') else ['npx', '--yes', 'supabase@3']
status = json.loads(subprocess.run(cli + ['status', '--output', 'json'], cwd=root, capture_output=True, text=True, check=True).stdout)
base = status['API_URL']
if base != 'http://127.0.0.1:54321': raise SystemExit('Refusing non-local Supabase')
public, service = status['PUBLISHABLE_KEY'], status['SERVICE_ROLE_KEY']
def request(path, method='GET', data=None, token=None, admin=False):
    headers = {'apikey': service if admin else public, 'content-type': 'application/json', 'prefer': 'return=representation'}
    if token or admin: headers['authorization'] = 'Bearer ' + (service if admin else token)
    q = urllib.request.Request(base + path, method=method, headers=headers, data=None if data is None else json.dumps(data).encode())
    try:
        with urllib.request.urlopen(q, timeout=20) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        return error.code, {}
def require(condition, message):
    if not condition: raise AssertionError(message)
email = f'budget-test-{time.time_ns()}@example.test'; password = 'synthetic-password-123'; uid = None
try:
    code, user = request('/auth/v1/admin/users', 'POST', {'email': email, 'password': password, 'email_confirm': True}, admin=True)
    require(code in (200, 201), 'cannot create test user'); uid = user['id']
    code, session = request('/auth/v1/token?grant_type=password', 'POST', {'email': email, 'password': password})
    require(code == 200, 'cannot log in'); token = session['access_token']
    code, categories = request('/rest/v1/categories?kind=eq.expense&select=id&limit=1', token=token)
    require(code == 200 and categories, 'missing test category'); category = categories[0]['id']
    code, accounts = request('/rest/v1/accounts', 'POST', {'name':'Synthetic','account_type':'cash','currency':'AMD','initial_balance':'0'}, token=token)
    require(code == 201 and accounts, 'cannot create account'); account = accounts[0]['id']
    payload = {'account_id':account,'category_id':category,'transaction_type':'expense','transaction_date':'2026-01-15','amount':'10.00','currency':'USD','account_amount':'4000.00','account_currency':'AMD'}
    code, _ = request('/rest/v1/transactions', 'POST', payload, token=token); require(code == 201, 'cannot create operation')
    code, _ = request('/rest/v1/rpc/save_budget_version', 'POST', {'p_category_id':category,'p_effective_month':'2026-01-01','p_currency':'AMD','p_amount':'5000'}, token=token)
    require(code == 200, 'cannot save budget')
    code, rows = request('/rest/v1/rpc/monthly_analytics_activity', 'POST', {'p_month':'2026-01-01'}, token=token)
    require(code == 200 and len(rows) == 1 and rows[0]['amount'] == '10.00' and rows[0]['account_amount'] == '4000.00', 'analytics lost precision or actual amount')
    code, rows = request('/rest/v1/rpc/effective_monthly_budgets', 'POST', {'p_month':'2026-02-01'}, token=token)
    require(code == 200 and len(rows) == 1 and rows[0]['currency'] == 'AMD' and rows[0]['amount'] == '5000', 'budget did not recur')
    print('Local budget API: exact amounts, actual account debit and recurring limit passed.')
finally:
    if uid: request('/auth/v1/admin/users/' + uid, 'DELETE', admin=True)
