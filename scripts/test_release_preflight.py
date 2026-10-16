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
        self.git('commit', '-q', '--allow-empty', '-m', 'base')
        self.base = self.git('rev-parse', 'HEAD')
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


if __name__ == '__main__':
    unittest.main()
