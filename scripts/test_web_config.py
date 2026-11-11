#!/usr/bin/env python3
import base64
import json
import unittest

from validate_web_config import validate


def jwt(role):
    payload = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
    return 'header.' + payload + '.signature'


class BuildConfigTest(unittest.TestCase):
    def test_accepts_public_key_and_legacy_anon(self):
        self.assertIsNone(validate('https://project.supabase.co', 'sb_publishable_example_123'))
        self.assertIsNone(validate('https://project.supabase.co', jwt('anon')))

    def test_rejects_privileged_keys(self):
        self.assertIsNotNone(validate('https://project.supabase.co', 'sb_secret_example'))
        self.assertIsNotNone(validate('https://project.supabase.co', jwt('service_role')))
        self.assertIsNotNone(validate('https://project.supabase.co', 'bad.key.data'))

    def test_requires_https_origin(self):
        self.assertIsNotNone(validate('http://localhost:54321', 'sb_publishable_example'))
        self.assertIsNotNone(validate('https://project.supabase.co/path', 'sb_publishable_example'))
        self.assertIsNotNone(validate('https://user:pass@project.supabase.co', 'sb_publishable_example'))


if __name__ == '__main__':
    unittest.main()
