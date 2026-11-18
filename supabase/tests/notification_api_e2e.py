#!/usr/bin/env python3
"""Local-only API test with synthetic notification data; never prints keys."""
import json, shutil, subprocess, time, urllib.error, urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[2]
cli=[shutil.which('supabase')] if shutil.which('supabase') else ['npx','--yes','supabase@3']
status=json.loads(subprocess.run(cli+['status','--output','json'],cwd=root,capture_output=True,text=True,check=True).stdout)
base=status['API_URL']
if base!='http://127.0.0.1:54321': raise SystemExit('Refusing non-local Supabase')
public=status['PUBLISHABLE_KEY']
service=status['SERVICE_ROLE_KEY']
def request(path,method='GET',data=None,token=None,admin=False):
 headers={'apikey':service if admin else public,'content-type':'application/json'}
 if token or admin:headers['authorization']='Bearer '+(service if admin else token)
 request=urllib.request.Request(base+path,method=method,headers=headers,data=None if data is None else json.dumps(data).encode())
 try:
  with urllib.request.urlopen(request,timeout=15) as r:
   raw=r.read();return r.status,json.loads(raw) if raw else None
 except urllib.error.HTTPError as e:
  return e.code,{}
def require(value,message):
 if not value:raise AssertionError(message)
email=f'notification-test-{time.time_ns()}@example.test';password='synthetic-password-123';uid=None
try:
 code,user=request('/auth/v1/admin/users','POST',{'email':email,'password':password,'email_confirm':True},admin=True)
 require(code in (200,201),'test user creation failed');uid=user['id']
 code,session=request('/auth/v1/token?grant_type=password','POST',{'email':email,'password':password})
 require(code==200,'test login failed');jwt=session['access_token']
 code,device=request('/rest/v1/rpc/register_notification_device','POST',{},token=jwt)
 require(code==200,'device registration failed')
 event={'event_key':'a'*64,'source':'acba','kind':'pre_purchase','amount':'100.25','currency':'AMD','merchant':'Synthetic Store','card_last4':'1111','occurred_at':'2026-01-01T12:00:00Z','time_source':'bank'}
 # Exactly the native client's headers: publishable key only, no user session.
 code,result=request('/rest/v1/rpc/ingest_notification_event','POST',{'p_device_token':device['device_token'],'p_event':event})
 require(code==200 and not result['duplicate'],f'background device upload failed ({code})')
 code,result=request('/rest/v1/rpc/ingest_notification_event','POST',{'p_device_token':device['device_token'],'p_event':event})
 require(code==200 and result['duplicate'],'event retry created a duplicate')
 code,rows=request('/rest/v1/notification_event_details?select=id,amount',token=jwt)
 require(code==200 and len(rows)==1 and rows[0]['amount']=='100.25','owner preview missing or imprecise')
 code,_=request('/rest/v1/rpc/revoke_notification_device','POST',{'p_device':device['device_id']},token=jwt)
 require(code==200,'device revocation failed')
 code,_=request('/rest/v1/rpc/ingest_notification_event','POST',{'p_device_token':device['device_token'],'p_event':event})
 require(code>=400,'revoked device accepted')
 print('Local notification API: publishable-key upload, deduplication and revocation passed.')
finally:
 if uid: request('/auth/v1/admin/users/'+uid,'DELETE',admin=True)
