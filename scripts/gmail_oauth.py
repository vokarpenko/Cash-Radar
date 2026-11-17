#!/usr/bin/env python3
"""Authorize the dedicated Gmail account; save credentials only to an ignored local file."""
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import secrets
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from getpass import getpass

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'supabase/functions/.env.gmail'
if TARGET.exists():
    raise SystemExit(f'{TARGET} already exists; back it up or remove it before reconnecting.')
print('Use only the dedicated Gmail mailbox created for bank statements.')
print('This requests Gmail read and label management access, including message contents.')
email = input('Dedicated Gmail address: ').strip().lower()
client_id = input('Google OAuth Desktop client ID: ').strip()
client_secret = getpass('Google OAuth Desktop client secret (hidden): ').strip()
if not email.endswith('@gmail.com') or email.count('@') != 1 or any(c.isspace() for c in email):
    raise SystemExit('Enter a valid dedicated @gmail.com address.')
if not client_id.endswith('.apps.googleusercontent.com') or not client_secret or any(c in client_id + client_secret for c in '\n\r="\''):
    raise SystemExit('Invalid OAuth client credentials.')
state = secrets.token_urlsafe(32)
verifier = secrets.token_urlsafe(64)
challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
result = {}
ready = threading.Event()
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass
    def do_GET(self):
        path = urllib.parse.urlparse(self.path)
        values = urllib.parse.parse_qs(path.query)
        if path.path != '/callback' or not secrets.compare_digest(values.get('state', [''])[0], state):
            self.send_error(400)
            return
        result['code'] = values.get('code', [''])[0]
        result['error'] = bool(values.get('error'))
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write('Return to the terminal to complete setup.'.encode())
        ready.set()
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
server.timeout = 1
redirect = f'http://127.0.0.1:{server.server_port}/callback'
params = urllib.parse.urlencode({'client_id':client_id,'redirect_uri':redirect,'response_type':'code','scope':'https://www.googleapis.com/auth/gmail.modify','access_type':'offline','prompt':'consent','state':state,'code_challenge':challenge,'code_challenge_method':'S256'})
url = 'https://accounts.google.com/o/oauth2/v2/auth?' + params
if not webbrowser.open(url):
    print('Open the authorization URL shown below in a browser:')
    print(url)
print('Approve access using the dedicated Gmail account. Waiting up to 3 minutes...')
import time
deadline = time.monotonic() + 180
while not ready.is_set() and time.monotonic() < deadline:
    server.handle_request()
server.server_close()
if not result.get('code') or result.get('error'):
    raise SystemExit('Authorization was cancelled or timed out; no credentials saved.')
form = urllib.parse.urlencode({'client_id':client_id,'client_secret':client_secret,'code':result['code'],'code_verifier':verifier,'grant_type':'authorization_code','redirect_uri':redirect}).encode()
try:
    with urllib.request.urlopen(urllib.request.Request('https://oauth2.googleapis.com/token',data=form,headers={'Content-Type':'application/x-www-form-urlencoded'}),timeout=15) as response:
        token = json.load(response)
    access = token['access_token']
    refresh = token['refresh_token']
    request = urllib.request.Request('https://gmail.googleapis.com/gmail/v1/users/me/profile',headers={'Authorization':'Bearer '+access})
    with urllib.request.urlopen(request,timeout=15) as response:
        profile = json.load(response)
    if profile.get('emailAddress', '').lower() != email:
        raise SystemExit('The authorized mailbox differs from the dedicated address; no credentials saved.')
    request = urllib.request.Request('https://gmail.googleapis.com/gmail/v1/users/me/labels',headers={'Authorization':'Bearer '+access})
    with urllib.request.urlopen(request,timeout=15) as response:
        labels = json.load(response).get('labels', [])
except (urllib.error.URLError, KeyError, ValueError):
    raise SystemExit('Google authorization failed; no credentials saved. Check client settings and try again.')
if not isinstance(refresh,str) or not refresh or any(c in refresh for c in '\n\r="\''):
    raise SystemExit('Google did not return a usable refresh token; no credentials saved.')
content = '\n'.join([f'GMAIL_CLIENT_ID={client_id}',f'GMAIL_CLIENT_SECRET={client_secret}',f'GMAIL_REFRESH_TOKEN={refresh}',f'GMAIL_EXPECTED_ADDRESS={email}',''])
fd = os.open(TARGET,os.O_WRONLY | os.O_CREAT | os.O_EXCL,0o600)
with os.fdopen(fd,'w',encoding='utf-8') as target:
    target.write(content)
print('Credentials saved to the Git-ignored file supabase/functions/.env.gmail (owner-only access).')
print('Available custom labels (create Gmail filters and labels before running this script):')
for label in labels:
    if label.get('type') == 'user' and isinstance(label.get('name'),str) and isinstance(label.get('id'),str):
        print(f"  {label['name']}: {label['id']}")
print('Do not share this file or its contents. Complete the local configuration as described in docs/gmail_collector.md.')
