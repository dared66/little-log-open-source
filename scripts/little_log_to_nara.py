#!/usr/bin/env python3
"""Convert a Little Log CSV to a Nara-shaped bridge JSON file, offline.

The result is a portable interchange/backup, not an upload to Nara Baby.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path, help='Little Log CSV')
    parser.add_argument('--output', required=True, type=Path, help='Bridge JSON output')
    parser.add_argument('--dart', default=shutil.which('dart') or 'dart')
    args = parser.parse_args(argv)
    completed = subprocess.run([args.dart, 'run', 'tool/history_bridge.dart', 'to-nara',
                                '--input', str(args.input), '--output', str(args.output)],
                               text=True, capture_output=True, cwd=ROOT, check=False)
    if completed.returncode:
        print(completed.stderr.strip() or 'Conversion failed.', file=sys.stderr)
        return 1
    print(completed.stdout.strip())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
