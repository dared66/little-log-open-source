"""Fail closed when the local Google configuration is missing from iOS builds."""

import json
from pathlib import Path
import plistlib
import subprocess
import sys
from configure_google import validate_config


ROOT = Path(__file__).resolve().parent.parent
GOOGLE_CONFIG = ROOT / 'config' / 'google.local.json'
REQUIRED_KEYS = (
    'GOOGLE_WEB_CLIENT_ID',
    'GOOGLE_IOS_CLIENT_ID',
    'GOOGLE_PROJECT_NUMBER',
)
GOOGLE_DEFINES = '--dart-define-from-file=config/google.local.json'


def require_google_config():
    if not GOOGLE_CONFIG.is_file():
        raise RuntimeError('Google configuration is missing; refusing to build an app without Drive.')
    config = json.loads(GOOGLE_CONFIG.read_text())
    validate_config(config)
    missing = [key for key in REQUIRED_KEYS
               if not isinstance(config.get(key), str) or not config[key].strip()]
    if missing:
        raise RuntimeError('Google configuration is incomplete: ' + ', '.join(missing))
    subprocess.run([sys.executable, str(ROOT / 'scripts' / 'configure_google.py')],
                   check=True, cwd=ROOT)
    reversed_id = '.'.join(reversed(config['GOOGLE_IOS_CLIENT_ID'].split('.')))
    callback = (ROOT / 'ios/Flutter/GoogleConfig.xcconfig').read_text()
    if f'GOOGLE_IOS_REVERSED_CLIENT_ID={reversed_id}\n' not in callback:
        raise RuntimeError('The iOS Google sign-in callback setting is incorrect.')
    return config


def verify_google_build(app, config, *, debug=False):
    """Check the built callback and compiled Dart definitions before install."""
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    expected = '.'.join(reversed(config['GOOGLE_IOS_CLIENT_ID'].split('.')))
    schemes = [scheme for entry in info.get('CFBundleURLTypes', [])
               for scheme in entry.get('CFBundleURLSchemes', [])]
    if expected not in schemes:
        raise RuntimeError('The built app is missing its Google sign-in callback.')
    binary = (app / 'Frameworks/App.framework'
              / ('flutter_assets/kernel_blob.bin' if debug else 'App'))
    contents = binary.read_bytes()
    missing = [key for key in ('GOOGLE_WEB_CLIENT_ID', 'GOOGLE_IOS_CLIENT_ID')
               if config[key].encode() not in contents]
    if missing:
        raise RuntimeError('The built app is missing Google client definitions: '
                           + ', '.join(missing))
    return info
