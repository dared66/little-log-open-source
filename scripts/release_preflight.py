"""Reject release sources that omit fixes already on the main branch."""

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def require_release_baseline(revision='HEAD', baseline='origin/main'):
    result = subprocess.run(
        ['git', 'merge-base', '--is-ancestor', baseline, revision],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode:
        missing = subprocess.run(
            ['git', 'log', '--oneline', f'{revision}..{baseline}'],
            cwd=ROOT, capture_output=True, text=True,
        )
        raise RuntimeError(
            f'Release source {revision} does not include {baseline}. '
            'Fetch origin and merge main before building.\n'
            + (missing.stdout.strip() or result.stderr.strip())
        )
    print(f'Release source {revision} includes {baseline}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision', default='HEAD')
    parser.add_argument('--baseline', default='origin/main')
    args = parser.parse_args()
    require_release_baseline(args.revision, args.baseline)


if __name__ == '__main__':
    main()
