"""The compatibility gate must reject a missing or weakened release fixture."""
from pathlib import Path
import shutil
import tempfile
import unittest

import check_build54_compatibility as compat


class Build54CompatibilityGateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in compat.FROZEN:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(compat.ROOT / name, target)

    def test_exact_released_reader_and_history_pass(self):
        compat.verify_frozen_build54(self.root)

    def test_weakened_reader_is_rejected(self):
        path = self.root / 'test/support/shared_log_builds_52_55/activity_details.dart'
        path.write_text(path.read_text().replace("'pumping' => <String>[]", "'pumping' => ['activeSeconds']"))
        # Ensure this is the same incompatibility that build 56 introduced.
        self.assertIn("'pumping' => ['activeSeconds']", path.read_text())
        with self.assertRaisesRegex(RuntimeError, 'Frozen build-54 fixture changed'):
            compat.verify_frozen_build54(self.root)

    def test_rewritten_history_is_rejected(self):
        path = self.root / 'test/support/build54_history_fixture.dart'
        path.write_text(path.read_text().replace('Synthetic compatibility family', 'Rewritten family'))
        with self.assertRaisesRegex(RuntimeError, 'Frozen build-54 fixture changed'):
            compat.verify_frozen_build54(self.root)

    def test_missing_fixture_is_rejected(self):
        (self.root / 'test/support/shared_log_builds_52_55/models.dart').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing frozen build-54 fixture'):
            compat.verify_frozen_build54(self.root)


if __name__ == '__main__':
    unittest.main()
