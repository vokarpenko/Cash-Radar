#!/usr/bin/env python3
"""Validate that a static Web build uses only public Supabase configuration."""
import base64
import json
import os
import re
import sys
from urllib.parse import urlparse


def validate(url, key):
    try:
        parsed = urlparse(url)
        hostname = parsed.hostname
    except ValueError:
        return 'SUPABASE_URL must be an HTTPS project origin.'
    if (parsed.scheme != 'https' or not hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or parsed.path not in ('', '/')
            or hostname in ('localhost', '127.0.0.1', '0.0.0.0')):
        return 'SUPABASE_URL must be an HTTPS project origin.'
    if re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]+', key):
        return None
    parts = key.split('.')
    if len(parts) == 3:
        try:
            payload = parts[1] + '=' * (-len(parts[1]) % 4)
            claims = json.loads(base64.urlsafe_b64decode(payload.encode('ascii')))
            if isinstance(claims, dict) and claims.get('role') == 'anon':
                return None
        except (ValueError, UnicodeError, TypeError):
            pass
    return 'SUPABASE_PUBLISHABLE_KEY must be a publishable or legacy anon key.'


def main():
    issue = validate(os.environ.get('SUPABASE_URL', ''), os.environ.get('SUPABASE_PUBLISHABLE_KEY', ''))
    if issue:
        print(issue, file=sys.stderr)
        return 1
    print('Public Supabase build configuration validated.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
