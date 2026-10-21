"""Require official releases to use current, audited public source."""

import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_REPOSITORY = 'dared66/little-log-open-source'
PUBLIC_ROOT = '6e47da94afe8735a4cbe8d093696617f0be29f6a'


def require_public_source(revision):
    """Official maintainer builds must not use retained private history."""
    remote = subprocess.run(
        ['git', 'remote', 'get-url', 'origin'], cwd=ROOT,
        capture_output=True, text=True,
    )
    allowed = re.fullmatch(
        r'(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)'
        + re.escape(PUBLIC_REPOSITORY) + r'(?:\.git)?/?',
        remote.stdout.strip(),
    )
    if remote.returncode or not allowed:
        raise RuntimeError(
            'Official release builds must use the public source repository '
            f'{PUBLIC_REPOSITORY}. Use its checkout and fetch public origin/main.'
        )
    ancestry = subprocess.run(
        ['git', 'merge-base', '--is-ancestor', PUBLIC_ROOT, revision],
        cwd=ROOT, capture_output=True, text=True,
    )
    if ancestry.returncode:
        raise RuntimeError(
            'Release source does not descend from the audited public snapshot. '
            'Changing the remote of an old private checkout does not sanitize '
            'its history; use a public-main-based branch.'
        )


def require_release_baseline(revision='HEAD', baseline='origin/main'):
    require_public_source(revision)
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
