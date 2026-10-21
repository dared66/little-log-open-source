"""A real Git graph must reject beta sources that omit already-merged fixes."""
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release_preflight


class ReleasePreflightTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Release test')
        self.git('config', 'user.email', 'release-test@example.invalid')
        self.git('remote', 'add', 'origin',
                 'https://github.com/dared66/little-log-open-source.git')
        self.git('commit', '-q', '--allow-empty', '-m', 'base')
        self.base = self.git('rev-parse', 'HEAD')
        patcher = patch.object(release_preflight, 'PUBLIC_ROOT', self.base)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.git('commit', '-q', '--allow-empty', '-m', 'merged UI fix')
        self.main = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.main)

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout.strip()

    def check(self, revision):
        with patch.object(release_preflight, 'ROOT', self.root):
            with contextlib.redirect_stdout(io.StringIO()):
                release_preflight.require_release_baseline(revision)

    def test_current_main_and_descendant_are_allowed(self):
        self.check(self.main)
        self.git('commit', '-q', '--allow-empty', '-m', 'new beta UI')
        self.check('HEAD')

    def test_stale_beta_is_rejected_and_names_missing_fix(self):
        self.git('checkout', '-q', '--detach', self.base)
        self.git('commit', '-q', '--allow-empty', '-m', 'stale beta')
        with self.assertRaisesRegex(RuntimeError, 'merged UI fix'):
            self.check('HEAD')

    def test_unknown_revision_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.check('missing-release-revision')

    def test_private_repository_is_rejected(self):
        self.git('remote', 'set-url', 'origin',
                 'https://github.com/dared66/little-log.git')
        with self.assertRaisesRegex(RuntimeError, 'public source repository'):
            self.check('HEAD')

    def test_lookalike_remote_is_rejected(self):
        self.git('remote', 'set-url', 'origin',
                 'https://github.com/dared66/little-log-open-source-fake.git')
        with self.assertRaisesRegex(RuntimeError, 'public source repository'):
            self.check('HEAD')

    def test_missing_origin_is_rejected(self):
        self.git('remote', 'remove', 'origin')
        with self.assertRaisesRegex(RuntimeError, 'public source repository'):
            self.check('HEAD')

    def test_ssh_public_origin_is_allowed(self):
        self.git('remote', 'set-url', 'origin',
                 'git@github.com:dared66/little-log-open-source.git')
        self.check('HEAD')

    def test_repointing_private_history_does_not_allow_release(self):
        self.git('checkout', '-q', '--orphan', 'private-history')
        self.git('commit', '-q', '--allow-empty', '-m', 'private starting point')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        with self.assertRaisesRegex(RuntimeError, 'audited public snapshot'):
            self.check('HEAD')


if __name__ == '__main__':
    unittest.main()
