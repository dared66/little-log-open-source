"""Fail CI if the externally released build-54 log contract is broken.

The frozen sources are checked by Git blob hash, without needing release tags in
CI's shallow checkout. Never regenerate them from current application code. A
larger internal build number does not change the public compatibility baseline.
"""

import hashlib
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
FROZEN = {
    'test/support/shared_log_builds_52_55/models.dart': '596da33a46b4fdf03ed4b53b96b4cb4d56d08174',
    'test/support/shared_log_builds_52_55/activity_details.dart': '4af8f93d55ea92b55370de0f6273728fbf174b95',
    'test/support/shared_log_builds_52_55/record_validation.dart': '5fe34744f9634b79030e5a8cdc5cd543d1ac033f',
    'test/support/shared_log_builds_52_55/diaper_details.dart': '0404eb201a4e3c3ee3c1559535d6544732748b70',
    'test/support/shared_log_builds_52_55/volume.dart': '5f947ce9e24b3c9f982bd501f407f79662e51b37',
    'test/support/shared_log_builds_52_55/services/family_csv.dart': '12e9ce48bddcd8e2fa454dd7be28db562cc10f33',
    'test/support/build54_history_fixture.dart': '8977a6bd836cb180373c0eaf0f829ac208eeac62',
}


def verify_frozen_build54(root=ROOT):
    for name, expected in FROZEN.items():
        path = root / name
        if not path.is_file():
            raise RuntimeError(f'Missing frozen build-54 fixture: {name}')
        data = path.read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if actual != expected:
            raise RuntimeError(
                f'Frozen build-54 fixture changed: {name}. '
                'Fix the new implementation; do not weaken the released reader or rewrite history.'
            )


def main():
    verify_frozen_build54()
    print('Verified exact released build-54 reader and synthetic history.', flush=True)
    subprocess.run([
        'flutter', 'test', '--no-pub', '--reporter', 'expanded',
        'test/released_build54_compatibility_test.dart',
        'test/pumping_compatibility_test.dart',
    ], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
