"""Check staged public files without printing private values.

CI checks the committed index. Maintainers can additionally supply their private
live-test settings to detect those exact values without publishing a denylist.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PRIVATE_SUFFIXES = {'.p8', '.p12', '.pem', '.key', '.jks', '.keystore', '.mobileprovision'}
# Public maintainer address explicitly approved on October 21, 2026.
PUBLIC_EMAILS = {'krupa@krupapc.dev', 'noreply@github.com'}
LIVE_ASSIGNMENT = re.compile(
    r'''["']?(LIVE_(?:ACCOUNT|OWNER|RECIPIENT|FILE_ID|QA_BABY))["']?\s*[:=]\s*["']([^"'\r\n]*)["']'''
)


def problems(name, data, private_values=()):
    path = PurePosixPath(name)
    issues = []
    if (any(part in {'.secrets', 'private-exports', '.aws'} for part in path.parts)
            or path.name == '.env' or path.name.startswith('.env.')
            or path.name.endswith('.local.json') or path.suffix in PRIVATE_SUFFIXES
            or name == 'android/key.properties'
            or path.name in {'google-services.json', 'GoogleService-Info.plist'}):
        issues.append('private configuration or key file')
    text = data.decode('utf-8', errors='replace')
    for match in LIVE_ASSIGNMENT.finditer(text):
        key, value = match.groups()
        if not value:
            continue
        if key in {'LIVE_ACCOUNT', 'LIVE_OWNER', 'LIVE_RECIPIENT'}:
            allowed = value.endswith('@example.com')
        elif key == 'LIVE_FILE_ID':
            allowed = value == 'YOUR_DISPOSABLE_TEST_FILE_ID'
        else:
            allowed = value == 'Synthetic QA baby'
        if not allowed:
            issues.append('non-example live-test setting')
    if any(value and value in data for value in private_values):
        issues.append('known private test reference')
    return sorted(set(issues))


def check_index(root, private_values=()):
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).split(b'\0')
    findings = []
    for raw in filter(None, paths):
        name = raw.decode('utf-8')
        data = subprocess.check_output(['git', 'show', ':' + name], cwd=root)
        findings.extend((name, issue) for issue in problems(name, data, private_values))
    return findings


def check_metadata(root, commit, private_values=()):
    data = subprocess.check_output([
        'git', 'show', '-s', '--format=%ae%x00%ce%x00%B', commit,
    ], cwd=root)
    author, committer, message = data.split(b'\0', 2)
    findings = []
    for kind, raw in (('author', author), ('committer', committer)):
        email = raw.decode('utf-8', errors='replace').strip()
        if (email not in PUBLIC_EMAILS
                and not re.fullmatch(r'[^@\s<>]+@users\.noreply\.github\.com', email)):
            findings.append((f'{commit[:12]}:metadata',
                             f'{kind} email is not an approved public identity'))
    if any(value and value in data for value in private_values):
        findings.append((f'{commit[:12]}:metadata', 'known private test reference'))
    return findings


def check_history(root, base, private_values=()):
    if base and not re.fullmatch(r'[0-9a-f]{40}', base):
        raise ValueError('Expected a full base commit SHA')
    span = f'{base}..HEAD' if base and base != '0' * 40 else 'HEAD'
    commits = subprocess.check_output(['git', 'rev-list', span], cwd=root).decode().splitlines()
    findings = []
    for commit in commits:
        findings.extend(check_metadata(root, commit, private_values))
        paths = subprocess.check_output([
            'git', 'diff-tree', '--root', '--no-commit-id', '--name-only',
            '--diff-filter=ACMRT', '-r', '-z', commit,
        ], cwd=root).split(b'\0')
        for raw in filter(None, paths):
            name = raw.decode('utf-8')
            data = subprocess.check_output(['git', 'show', commit + ':' + name], cwd=root)
            findings.extend((f'{commit[:12]}:{name}', issue)
                            for issue in problems(name, data, private_values))
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-config', type=Path)
    parser.add_argument('--base', help='Also check every new commit, including files later removed')
    args = parser.parse_args()
    values = []
    if args.private_config:
        settings = json.loads(args.private_config.read_text())
        for key in ('LIVE_ACCOUNT', 'LIVE_OWNER', 'LIVE_RECIPIENT', 'LIVE_FILE_ID', 'LIVE_QA_BABY'):
            value = settings.get(key)
            if value:
                values.append(value.encode())
    findings = check_index(ROOT, values)
    if args.base is not None:
        findings.extend(check_history(ROOT, args.base, values))
    for name, issue in findings:
        print(f'{name}: {issue}')
    if findings:
        raise SystemExit(1)
    print('Public-source file and live-test setting checks passed.')


if __name__ == '__main__':
    main()
