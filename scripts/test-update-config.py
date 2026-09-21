#!/usr/bin/env python3
"""Validate release configuration without network access or signing keys."""
import base64
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('update_config', Path(__file__).with_name('configure-updates.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UpdateConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.env = {'DYNOMITE_FEED_URL': 'https://example.com/appcast.xml',
                    'DYNOMITE_UPDATE_PUBLIC_KEY': base64.b64encode(bytes(32)).decode()}

    def test_unconfigured_build_has_no_feed(self):
        self.assertEqual(module.configure({'CFBundleVersion': '1'}, {}), {'CFBundleVersion': '1'})

    def test_valid_release_preserves_identifier_and_sets_trust(self):
        self.env.update(DYNOMITE_VERSION='1.2.3', DYNOMITE_BUILD_NUMBER='42')
        info = module.configure({'CFBundleIdentifier': 'com.example.App'}, self.env)
        self.assertEqual(info['CFBundleIdentifier'], 'com.example.App')
        self.assertEqual(info['CFBundleVersion'], '42')
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
        self.assertFalse(info['SUSendProfileInfo'])
        self.assertFalse(info['SUEnableAutomaticChecks'])

    def test_partial_configuration_is_rejected(self):
        for key in self.env:
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.configure({}, {key: self.env[key]})

    def test_unsafe_feeds_are_rejected(self):
        for feed in ['http://example.com/feed', 'https:///feed', 'https://user:password@example.com/feed',
                     'file:///tmp/feed', 'https://example.com/feed#fragment']:
            with self.subTest(feed=feed), self.assertRaises(ValueError):
                module.configure({}, {**self.env, 'DYNOMITE_FEED_URL': feed})

    def test_invalid_key_is_rejected(self):
        for key in ['bad key', base64.b64encode(bytes(31)).decode()]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.configure({}, {**self.env, 'DYNOMITE_UPDATE_PUBLIC_KEY': key})

    def test_invalid_build_is_rejected(self):
        for build in ['', '../2', '1..2', 'next']:
            with self.subTest(build=build), self.assertRaises(ValueError):
                module.configure({}, {**self.env, 'DYNOMITE_BUILD_NUMBER': build})


if __name__ == '__main__':
    unittest.main()
