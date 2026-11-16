#!/usr/bin/env python3
"""Local-only HTTP test: creates and removes isolated synthetic users."""
import json
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[2]
cli = [shutil.which('supabase')] if shutil.which('supabase') else ['npx', '--yes', 'supabase@3']
config = json.loads(subprocess.run(cli + ['status', '--output', 'json'], cwd=root, capture_output=True, text=True, check=True).stdout)
base, anon, admin = config['API_URL'], config['ANON_KEY'], config['SERVICE_ROLE_KEY']
url = urllib.parse.urlparse(base)
if url.scheme != 'http' or url.hostname not in ('localhost', '127.0.0.1') or url.port != 54321:
    raise SystemExit('Refusing to run outside local Supabase')
users = []

def request(path, method='GET', data=None, token=None, service=False):
    headers = {'apikey': admin if service else anon, 'Content-Type': 'application/json', 'Prefer': 'return=representation'}
    if service or token:
        headers['Authorization'] = 'Bearer ' + (admin if service else token)
    req = urllib.request.Request(base+path, data=None if data is None else json.dumps(data).encode(), method=method, headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=20) as response:
            body=response.read()
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        body=error.read()
        try: return error.code, json.loads(body) if body else None
        except ValueError: return error.code, None

def require(ok, message):
    if not ok: raise AssertionError(message)

def create_user():
    email=f'cash-transfer-{uuid.uuid4()}@example.test'; password='Local-transfer-123!'
    code, data=request('/auth/v1/admin/users','POST',{'email':email,'password':password,'email_confirm':True},service=True)
    require(code in (200,201) and data.get('id'), 'Could not create synthetic user')
    user=data['id']; users.append(user)
    code, data=request('/auth/v1/token?grant_type=password','POST',{'email':email,'password':password})
    require(code==200,'Synthetic login failed')
    return user,data['access_token']

def account(token, name, currency, initial):
    code, data=request('/rest/v1/accounts?select=id','POST',{'name':name,'account_type':'cash','currency':currency,'initial_balance':initial},token=token)
    require(code==201 and len(data)==1,'Could not create synthetic account')
    return data[0]['id']

try:
    _, a=create_user(); _, b=create_user()
    source=account(a,'Synthetic AMD','AMD','1000'); dest=account(a,'Synthetic USD','USD','0'); foreign=account(b,'Other','AMD','0')
    payload={'p_from':source,'p_to':dest,'p_date':'2026-11-01','p_from_amount':'400.00','p_to_amount':'1.00','p_fee':'2.00','p_description':'Synthetic transfer','p_request_id':str(uuid.uuid4())}
    code, group=request('/rest/v1/rpc/create_manual_transfer','POST',payload,token=a)
    require(code==200 and isinstance(group,str),'Transfer API failed')
    code, again=request('/rest/v1/rpc/create_manual_transfer','POST',payload,token=a)
    require(code==200 and again==group,'Transfer retry duplicated operations')
    code, groups=request('/rest/v1/transfer_group_details?select=id,debit_amount,credit_amount,fee_amount',token=a)
    require(code==200 and len(groups)==1 and groups[0]['id']==group,'Transfer group missing')
    code, summary=request('/rest/v1/income_expense_transactions?select=id',token=a)
    require(code==200 and len(summary)==1,'Transfer legs included in statistics')
    code, balances=request('/rest/v1/account_balances?select=id,current_balance',token=a)
    values={x['id']:float(x['current_balance']) for x in balances}
    require(code==200 and values[source]==598 and values[dest]==1,'Incorrect account balances')
    code, details=request('/rest/v1/transaction_details?select=id,transfer_group_id,transfer_fee_group_id',token=a)
    require(code==200 and sum(x['transfer_group_id']==group for x in details)==2 and sum(x['transfer_fee_group_id']==group for x in details)==1,'Transfer metadata missing')
    debit=next(x['id'] for x in details if x['transfer_group_id']==group)
    code, _=request('/rest/v1/transactions?id=eq.'+debit,'PATCH',{'raw_description':'Synthetic change'},token=a)
    require(code>=400,'Linked operation was editable')
    code, foreign_groups=request('/rest/v1/transfer_group_details?select=id',token=b)
    require(code==200 and not foreign_groups,'Foreign user saw transfer')
    bad=dict(payload,p_to=foreign,p_request_id=str(uuid.uuid4()))
    code, _=request('/rest/v1/rpc/create_manual_transfer','POST',bad,token=a)
    require(code>=400,'Foreign account was accepted')
    code, _=request('/rest/v1/rpc/unlink_transfer','POST',{'p_id':group},token=b)
    require(code>=400,'Foreign user unlinked transfer')
    print('Local transfer HTTP tests passed: balances, fee, retries and isolation.')
finally:
    cleanup_failed = False
    for user in users:
        code, _=request('/auth/v1/admin/users/'+user,'DELETE',service=True)
        if code not in (200,204): cleanup_failed = True
    if cleanup_failed: raise RuntimeError('Could not remove a synthetic test user')
