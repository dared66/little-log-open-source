import subprocess
import tempfile
from pathlib import Path
import unittest

from check_public_source import check_history, check_index, check_metadata, problems


class PublicSourceTest(unittest.TestCase):
    def test_private_file_names_are_blocked_even_when_force_added(self):
        for name in ('config/google.local.json', '.secrets/signing.p8',
                     'android/key.properties', '.env.production',
                     'private-exports/baby.csv', 'android/app/google-services.json'):
            with self.subTest(name=name):
                self.assertTrue(problems(name, b'{}'))

    def test_synthetic_settings_are_allowed(self):
        source = b'{"LIVE_ACCOUNT":"tester@example.com","LIVE_FILE_ID":"","LIVE_QA_BABY":"Synthetic QA baby"}'
        self.assertEqual([], problems('config/live-tests.example.json', source))

    def test_nonexample_account_and_file_settings_are_blocked(self):
        for key, value in (('LIVE_ACCOUNT', 'tester@invalid.test'),
                           ('LIVE_FILE_ID', 'synthetic-but-not-a-placeholder')):
            with self.subTest(key=key):
                source = ('{"' + key + '":"' + value + '"}').encode()
                self.assertIn('non-example live-test setting', problems('settings.json', source))

    def test_optional_private_values_are_detected_without_echoing(self):
        value = b'synthetic-reference-for-this-test'
        issues = problems('notes.txt', b'Copied ' + value, [value])
        self.assertEqual(['known private test reference'], issues)
        self.assertNotIn(value.decode(), str(issues))

    def test_checks_staged_content_even_if_working_copy_is_cleaned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            path = root / 'settings.json'
            path.write_text('{"LIVE_FILE_ID":"' + 'synthetic-staged-reference' + '"}')
            subprocess.run(['git', 'add', 'settings.json'], cwd=root, check=True)
            path.write_text('{}')
            self.assertEqual([('settings.json', 'non-example live-test setting')], check_index(root))

    def test_catches_private_file_added_and_removed_in_new_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-c', 'user.name=Test',
                    '-c', 'user.email=test@users.noreply.github.com', *args], cwd=root)
            git('init', '-q')
            git('commit', '-q', '--allow-empty', '-m', 'baseline')
            base = git('rev-parse', 'HEAD').decode().strip()
            (root / '.env').write_text('SYNTHETIC=1')
            git('add', '.env')
            git('commit', '-q', '-m', 'synthetic private file')
            git('rm', '-q', '.env')
            git('commit', '-q', '-m', 'remove file')
            self.assertEqual([], check_index(root))
            findings = check_history(root, base)
            self.assertEqual(1, len(findings))
            self.assertEqual('private configuration or key file', findings[0][1])

    def test_metadata_blocks_unapproved_emails_without_printing_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-c', 'user.name=Test',
                    '-c', 'user.email=public@users.noreply.github.com', *args], cwd=root)
            git('init', '-q')
            git('commit', '-q', '--allow-empty', '-m', 'public baseline')
            self.assertEqual([], check_metadata(root, 'HEAD'))
            git('-c', 'user.email=private@example.invalid', 'commit', '-q',
                '--allow-empty', '--author=Public <public@users.noreply.github.com>',
                '-m', 'safe source, unsafe committer')
            findings = check_metadata(root, 'HEAD')
            self.assertEqual(1, len(findings))
            self.assertIn('committer email', findings[0][1])
            self.assertNotIn('private@example.invalid', str(findings))
            git('commit', '-q', '--allow-empty',
                '--author=Private <private@example.invalid>', '-m', 'unsafe author')
            self.assertIn('author email', check_metadata(root, 'HEAD')[0][1])

    def test_public_maintainer_identity_and_known_private_message(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-c', 'user.name=Test',
                    '-c', 'user.email=krupa@krupapc.dev', *args], cwd=root)
            git('init', '-q')
            git('commit', '-q', '--allow-empty', '-m', 'synthetic-private-reference')
            self.assertEqual([], check_metadata(root, 'HEAD'))
            self.assertEqual('known private test reference',
                check_metadata(root, 'HEAD', [b'synthetic-private-reference'])[0][1])


if __name__ == '__main__':
    unittest.main()
