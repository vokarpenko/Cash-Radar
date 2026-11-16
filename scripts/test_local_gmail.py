#!/usr/bin/env python3
"""Run Gmail integration against local Supabase; never print its service key."""
import json
import os
from pathlib import Path
import subprocess
import shutil
root = Path(__file__).resolve().parents[1]
status = subprocess.run(['npx','--yes','supabase@3','status','--output','json'],cwd=root,capture_output=True,text=True,check=True)
values = json.loads(status.stdout)
if values.get('API_URL') != 'http://127.0.0.1:54321':
    raise SystemExit('Refusing to test against a non-local Supabase')
env = os.environ.copy()
env.update(SUPABASE_URL=values['API_URL'],SUPABASE_ANON_KEY=values['ANON_KEY'],SUPABASE_SERVICE_ROLE_KEY=values['SERVICE_ROLE_KEY'])
deno = [shutil.which('deno')] if shutil.which('deno') else ['npx','--yes','deno@2']
subprocess.run(deno+['run','--allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY','--allow-net=127.0.0.1:54321','--allow-read=supabase/tests/fixtures/alfa_synthetic.xlsx','supabase/tests/gmail_local_e2e.ts'],cwd=root,env=env,check=True)
