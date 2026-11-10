#!/usr/bin/env python3
"""Write only public local Supabase settings to an ignored Flutter config file."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
output = root / 'app' / 'config' / 'local-supabase.json'
if output.exists():
    print(f'{output} already exists; leaving it unchanged.')
    sys.exit(0)
env = os.environ.copy()
env['SUPABASE_EXPERIMENTAL_STACK'] = '0'
result = subprocess.run(
    ['npx', '--yes', 'supabase@3', 'status', '-o', 'env'],
    cwd=root, env=env, capture_output=True, text=True,
)
if result.returncode:
    sys.exit('Could not read Supabase status. Start the local stack first.')
values = {}
for line in result.stdout.splitlines():
    if '=' in line:
        key, value = line.split('=', 1)
        values[key] = value.strip('"')
url = values.get('API_URL', '')
key = values.get('PUBLISHABLE_KEY') or values.get('ANON_KEY')
if url != 'http://127.0.0.1:54321' or not key:
    sys.exit('Unexpected local API address or missing public key; configuration not written.')
payload = json.dumps({
    'SUPABASE_URL': url,
    'SUPABASE_PUBLISHABLE_KEY': key,
    'ALLOW_INSECURE_LOCAL_SUPABASE': 'true',
}, indent=2) + '\n'
try:
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    sys.exit('Local configuration appeared during setup; leaving it unchanged.')
with os.fdopen(fd, 'w', encoding='utf-8') as file:
    file.write(payload)
print(f'Created {output} with the local public configuration.')
