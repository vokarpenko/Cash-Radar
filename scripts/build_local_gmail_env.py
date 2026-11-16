#!/usr/bin/env python3
"""Merge local Edge secrets without printing their values or changing the originals."""
import os
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'supabase/functions'
values = {}
for name in ('.env', '.env.gmail'):
    path = root / name
    if not path.exists():
        continue
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.lstrip().startswith('#'):
            continue
        if '=' not in line:
            raise SystemExit(f'Invalid line in {name}; no runtime file written.')
        key, value = line.split('=', 1)
        if not key or not key.replace('_', '').isalnum():
            raise SystemExit(f'Invalid key in {name}; no runtime file written.')
        if key in values and values[key] != value:
            raise SystemExit(f'Duplicate key {key} differs between local files; no runtime file written.')
        values[key] = value
if not values.get('GMAIL_REFRESH_TOKEN'):
    raise SystemExit('Gmail is not connected; no runtime file written.')
target = root / '.env.gmail-runtime'
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.fchmod(fd, 0o600)
with os.fdopen(fd, 'w', encoding='utf-8') as out:
    for key, value in values.items():
        out.write(f'{key}={value}\n')
print('Local runtime configuration is ready; secret values were not displayed.')
