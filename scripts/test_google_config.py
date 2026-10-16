"""Protect the test-to-production switch and iOS build definitions."""
import contextlib
import io
import json
import plistlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import configure_google
import ios_build_config


class GoogleConfigTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'config').mkdir()
        (self.root / 'ios/Flutter').mkdir(parents=True)
        self.production = json.loads((configure_google.ROOT / 'config/google.production.json').read_text())
        (self.root / 'config/google.production.json').write_text(json.dumps(self.production))

    def activate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return configure_google.configure(self.root, production=True)

    def test_switch_preserves_testing_and_drops_testing_picker_key(self):
        testing = dict(self.production,
                       GOOGLE_CLOUD_PROJECT_ID='test-project',
                       GOOGLE_PROJECT_NUMBER='123',
                       GOOGLE_WEB_CLIENT_ID='123-web.apps.googleusercontent.com',
                       GOOGLE_IOS_CLIENT_ID='123-ios.apps.googleusercontent.com',
                       GOOGLE_PICKER_API_KEY='synthetic-testing-key',
                       PLAY_BILLING_PUBLIC_KEY='synthetic-billing-key')
        original = json.dumps(testing)
        (self.root / 'config/google.local.json').write_text(original)
        selected = self.activate()
        self.assertEqual((self.root / 'config/google.testing.local.json').read_text(), original)
        self.assertEqual(selected['GOOGLE_PICKER_API_KEY'], '')
        self.assertEqual(selected['PLAY_BILLING_PUBLIC_KEY'], testing['PLAY_BILLING_PUBLIC_KEY'])
        callback = (self.root / 'ios/Flutter/GoogleConfig.xcconfig').read_text()
        self.assertIn('.'.join(reversed(self.production['GOOGLE_IOS_CLIENT_ID'].split('.'))), callback)

    def test_repeat_selection_preserves_production_web_key(self):
        self.activate()
        current = dict(self.production, GOOGLE_PICKER_API_KEY='synthetic-production-key')
        (self.root / 'config/google.local.json').write_text(json.dumps(current))
        self.assertEqual(self.activate()['GOOGLE_PICKER_API_KEY'], 'synthetic-production-key')

    def test_existing_tester_identity_is_the_release_identity(self):
        self.assertEqual(self.production['GOOGLE_CLOUD_PROJECT_ID'], 'little-log-509004')
        self.assertEqual(self.production['GOOGLE_PROJECT_NUMBER'], '259649378161')
        current = dict(self.production, GOOGLE_PICKER_API_KEY='existing-project-key')
        current.pop('GOOGLE_CLOUD_PROJECT_ID')
        (self.root / 'config/google.local.json').write_text(json.dumps(current))
        selected = self.activate()
        for key in configure_google.CLIENT_KEYS:
            self.assertEqual(selected[key], current[key])
        self.assertEqual(selected['GOOGLE_PICKER_API_KEY'], 'existing-project-key')
        self.assertFalse((self.root / 'config/google.testing.local.json').exists())

    def test_retired_project_cannot_be_selected_for_a_release(self):
        retired = dict(self.production, GOOGLE_CLOUD_PROJECT_ID='little-log-production-509904',
                       GOOGLE_PROJECT_NUMBER='871569601653',
                       GOOGLE_WEB_CLIENT_ID='871569601653-web.apps.googleusercontent.com',
                       GOOGLE_IOS_CLIENT_ID='871569601653-ios.apps.googleusercontent.com')
        with self.assertRaisesRegex(ValueError, 'retired'):
            configure_google.validate_config(retired)

    def test_mixed_projects_and_stale_production_ids_are_rejected(self):
        for config in [dict(self.production, GOOGLE_IOS_CLIENT_ID='123-ios.apps.googleusercontent.com'),
                       dict(self.production, GOOGLE_PROJECT_NUMBER='123'),
                       dict(self.production, GOOGLE_WEB_CLIENT_ID='871569601653-stale.apps.googleusercontent.com'),
                       dict(self.production, GOOGLE_IOS_CLIENT_ID='secret'),
                       dict(self.production, GOOGLE_IOS_CLIENT_ID=None)]:
            with self.subTest(config=config), self.assertRaises(ValueError):
                configure_google.validate_config(config)

    def test_ios_accepts_production_without_web_picker_key(self):
        self.activate()
        with patch.object(ios_build_config, 'ROOT', self.root), \
             patch.object(ios_build_config, 'GOOGLE_CONFIG', self.root / 'config/google.local.json'), \
             patch.object(ios_build_config.subprocess, 'run'):
            self.assertEqual(ios_build_config.require_google_config(), self.production)

    def test_ios_rejects_missing_client_before_build(self):
        self.activate()
        incomplete = dict(self.production, GOOGLE_CLOUD_PROJECT_ID='', GOOGLE_IOS_CLIENT_ID='')
        (self.root / 'config/google.local.json').write_text(json.dumps(incomplete))
        with patch.object(ios_build_config, 'GOOGLE_CONFIG', self.root / 'config/google.local.json'), \
             self.assertRaises(RuntimeError):
            ios_build_config.require_google_config()

    def test_conflicting_backup_fails_without_changing_active_configuration(self):
        testing = dict(self.production, GOOGLE_CLOUD_PROJECT_ID='test-project',
                       GOOGLE_PROJECT_NUMBER='123',
                       GOOGLE_WEB_CLIENT_ID='123-web.apps.googleusercontent.com',
                       GOOGLE_IOS_CLIENT_ID='123-ios.apps.googleusercontent.com')
        original = json.dumps(testing)
        (self.root / 'config/google.local.json').write_text(original)
        (self.root / 'config/google.testing.local.json').write_text('older backup')
        with self.assertRaisesRegex(ValueError, 'backup already exists'):
            self.activate()
        self.assertEqual((self.root / 'config/google.local.json').read_text(), original)
        self.assertEqual((self.root / 'config/google.testing.local.json').read_text(), 'older backup')

    def test_invalid_old_config_cannot_be_silently_replaced(self):
        original = '{invalid json'
        (self.root / 'config/google.local.json').write_text(original)
        with self.assertRaises(ValueError):
            self.activate()
        self.assertEqual((self.root / 'config/google.local.json').read_text(), original)

    def test_invalid_types_and_client_shapes_are_rejected(self):
        for config in [[], None, 'secret',
                       dict(self.production, GOOGLE_WEB_CLIENT_ID=123),
                       dict(self.production, GOOGLE_WEB_CLIENT_ID='123-client.secret'),
                       dict(self.production, GOOGLE_PROJECT_NUMBER=871569601653),
                       dict(self.production, GOOGLE_PROJECT_NUMBER='project-id')]:
            with self.subTest(config=config), self.assertRaises(ValueError):
                configure_google.validate_config(config)

    def test_empty_generic_config_disables_callback_but_cannot_pass_ios_preflight(self):
        (self.root / 'config/google.local.json').write_text('{}')
        with contextlib.redirect_stdout(io.StringIO()):
            configure_google.configure(self.root)
        self.assertIn('GOOGLE_IOS_REVERSED_CLIENT_ID=\n',
                      (self.root / 'ios/Flutter/GoogleConfig.xcconfig').read_text())
        with patch.object(ios_build_config, 'GOOGLE_CONFIG', self.root / 'config/google.local.json'), \
             self.assertRaisesRegex(RuntimeError, 'incomplete'):
            ios_build_config.require_google_config()

    def test_existing_identical_testing_backup_is_safe_and_repeatable(self):
        testing = dict(self.production, GOOGLE_CLOUD_PROJECT_ID='test-project',
                       GOOGLE_PROJECT_NUMBER='123',
                       GOOGLE_WEB_CLIENT_ID='123-web.apps.googleusercontent.com',
                       GOOGLE_IOS_CLIENT_ID='123-ios.apps.googleusercontent.com')
        original = json.dumps(testing)
        for name in ['google.local.json', 'google.testing.local.json']:
            (self.root / 'config' / name).write_text(original)
        self.activate()
        self.activate()
        self.assertEqual((self.root / 'config/google.testing.local.json').read_text(), original)

    def test_stale_test_callback_fails_ios_preflight(self):
        self.activate()
        (self.root / 'ios/Flutter/GoogleConfig.xcconfig').write_text(
            'GOOGLE_IOS_REVERSED_CLIENT_ID=com.googleusercontent.apps.123-ios\n')
        with patch.object(ios_build_config, 'ROOT', self.root), \
             patch.object(ios_build_config, 'GOOGLE_CONFIG', self.root / 'config/google.local.json'), \
             patch.object(ios_build_config.subprocess, 'run'), \
             self.assertRaisesRegex(RuntimeError, 'callback setting is incorrect'):
            ios_build_config.require_google_config()

    def built_app(self, schemes, binary):
        app = self.root / 'Runner.app'
        (app / 'Frameworks/App.framework/flutter_assets').mkdir(parents=True, exist_ok=True)
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleURLTypes': [{'CFBundleURLSchemes': schemes}]}))
        (app / 'Frameworks/App.framework/App').write_bytes(binary)
        (app / 'Frameworks/App.framework/flutter_assets/kernel_blob.bin').write_bytes(binary)
        return app

    def test_debug_and_release_artifacts_contain_both_production_ids(self):
        callback = '.'.join(reversed(self.production['GOOGLE_IOS_CLIENT_ID'].split('.')))
        ids = ' '.join(self.production[name] for name in configure_google.CLIENT_KEYS).encode()
        app = self.built_app([callback], ids)
        for debug in [False, True]:
            ios_build_config.verify_google_build(app, self.production, debug=debug)

    def test_test_project_callback_is_rejected_in_built_app(self):
        app = self.built_app(['com.googleusercontent.apps.123-ios'], b'synthetic')
        with self.assertRaisesRegex(RuntimeError, 'missing its Google sign-in callback'):
            ios_build_config.verify_google_build(app, self.production)

    def test_each_missing_compiled_client_id_is_rejected(self):
        callback = '.'.join(reversed(self.production['GOOGLE_IOS_CLIENT_ID'].split('.')))
        for missing in configure_google.CLIENT_KEYS:
            contents = ' '.join(self.production[name] for name in configure_google.CLIENT_KEYS
                                if name != missing).encode()
            app = self.built_app([callback], contents)
            with self.subTest(missing=missing), self.assertRaisesRegex(RuntimeError, missing):
                ios_build_config.verify_google_build(app, self.production)


if __name__ == '__main__':
    unittest.main()
