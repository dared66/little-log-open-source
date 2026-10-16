#!/usr/bin/env python3
"""Apply non-secret Google client IDs from ignored local build configuration."""
import json
import plistlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config_path = root / 'config/google.local.json'
if not config_path.exists():
    raise SystemExit('Create config/google.local.json from config/google.example.json first.')
config = json.loads(config_path.read_text())
web = config.get('GOOGLE_WEB_CLIENT_ID', '')
ios = config.get('GOOGLE_IOS_CLIENT_ID', '')
for name, value in [('GOOGLE_WEB_CLIENT_ID', web), ('GOOGLE_IOS_CLIENT_ID', ios)]:
    if value and not value.endswith('.apps.googleusercontent.com'):
        raise SystemExit(f'{name} must be an OAuth client ID, not a client secret or token.')
if ios:
    plist_path = root / 'ios/Runner/Info.plist'
    plist = plistlib.loads(plist_path.read_bytes())
    reversed_id = '.'.join(reversed(ios.split('.')))
    # Keep unrelated URL registrations intact on subsequent edits.
    types = [item for item in plist.get('CFBundleURLTypes', [])
             if item.get('CFBundleURLName') != 'google-signin']
    types.append({'CFBundleURLName': 'google-signin', 'CFBundleURLSchemes': [reversed_id]})
    plist['CFBundleURLTypes'] = types
    plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
    print('Configured iOS Google callback URL scheme.')
print('Client configuration validated. Build with --dart-define-from-file=config/google.local.json.')
