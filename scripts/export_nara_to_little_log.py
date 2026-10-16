#!/usr/bin/env python3
"""Read one child from the installed Nara skill and create a Little Log CSV.

The Nara client is always read-only. No credential or raw record is printed.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SKILL = Path.home() / '.codex/skills/nara-baby'
PREFS = Path.home() / '.config/nara-baby/preferences.json'


def select_export(api, name):
    children = api.get_children()
    matches = [(key, profile) for key, profile in children.items()
               if isinstance(profile, dict) and profile.get('name', '').casefold() == name.casefold()]
    if len(matches) != 1:
        raise ValueError('Baby name did not identify exactly one Nara profile.')
    child_key, profile = matches[0]
    tracks = {key: value for key, value in api.get_data().items()
              if isinstance(value, dict) and value.get('childKey') == child_key}
    return {'profile': profile, 'tracks': tracks}


def fetch(name, skill_dir, timezone=None, family=None):
    scripts = skill_dir / 'scripts'
    if not (scripts / 'nara_client.py').is_file():
        raise RuntimeError('The installed nara-baby skill was not found.')
    config = {}
    if PREFS.is_file():
        config = json.loads(PREFS.read_text())
        if not isinstance(config, dict):
            raise RuntimeError('Nara preferences are invalid.')
    # Read only known non-secret fields. Older preferences may contain other keys.
    selected_zone = timezone or config.get('timezone')
    if not selected_zone:
        raise RuntimeError('Provide --timezone (an IANA timezone such as America/Los_Angeles).')
    sys.path.insert(0, str(scripts))
    from nara_client import connected_client
    with connected_client(family=family or config.get('family'), timezone_name=selected_zone) as api:
        result = select_export(api, name)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child', required=True, help='Verified child profile name')
    parser.add_argument('--output', required=True, type=Path, help='Local Little Log CSV output')
    parser.add_argument('--base-csv', type=Path, help='Existing Little Log CSV to preserve and extend')
    parser.add_argument('--caregivers', type=Path, help='Optional JSON mapping of Nara caregiver IDs to display names')
    parser.add_argument('--timezone', help='IANA timezone (defaults to the Nara skill preference)')
    parser.add_argument('--family', help='Nara family key if more than one family is connected')
    parser.add_argument('--skill-dir', type=Path, default=DEFAULT_SKILL)
    parser.add_argument('--dart', default=shutil.which('dart') or 'dart')
    args = parser.parse_args(argv)
    try:
        export = fetch(args.child, args.skill_dir, args.timezone, args.family)
        command = [args.dart, 'run', 'tool/history_bridge.dart', 'from-nara', '--input', '-', '--output', str(args.output)]
        if args.base_csv:
            command += ['--base-csv', str(args.base_csv)]
        if args.caregivers:
            command += ['--caregivers', str(args.caregivers)]
        completed = subprocess.run(command, input=json.dumps(export), text=True,
                                   capture_output=True, cwd=ROOT, check=False)
        if completed.returncode:
            raise RuntimeError(completed.stderr.strip() or 'Little Log conversion failed.')
        print(completed.stdout.strip())
        return 0
    except Exception as exc:
        print(f'Export failed: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
