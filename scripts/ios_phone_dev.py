"""Build and install Little Log on the configured iPhone without Xcode login.

The existing Apple API key stays outside the repository. This script reuses
local development profiles until they near expiry, then refreshes them through
App Store Connect. It never deletes the installed app or its data container.
"""

import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import venv
from ios_build_config import GOOGLE_DEFINES, require_google_config, verify_google_build
from release_preflight import require_release_baseline


ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'config' / 'ios_dev.local.json'
PROFILE_DIR = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
PROFILE_NAMES = {
    'app.littlelog.littleLog': 'Little Log Development',
    'app.littlelog.littleLog.TimerActivity': 'Little Log Timer Development',
}


def run(*command, capture=False):
    return subprocess.run(command, check=True, text=True,
                          capture_output=capture)


def profile_valid(profile, identifier, name, device, team):
    result = subprocess.run(
        ['security', 'cms', '-D', '-i', str(profile)],
        capture_output=True,
    )
    if result.returncode:
        return False
    try:
        data = plistlib.loads(result.stdout)
        expiry = data['ExpirationDate'].replace(tzinfo=timezone.utc)
        return (data.get('Name') == name
                and data.get('TeamIdentifier', [None])[0] == team
                and data.get('Entitlements', {}).get('application-identifier')
                    == f'{team}.{identifier}'
                and device in data.get('ProvisionedDevices', [])
                and expiry > datetime.now(timezone.utc) + timedelta(days=30))
    except (KeyError, ValueError, TypeError):
        return False


def missing_profiles(config):
    return {
        identifier: name
        for identifier, name in PROFILE_NAMES.items()
        if not any(profile_valid(path, identifier, name,
                                 config['device_udid'], config['team_id'])
                   for path in PROFILE_DIR.glob('*.mobileprovision'))
    }


def phone_connected(device_udid):
    with tempfile.TemporaryDirectory() as directory:
        listing = Path(directory) / 'devices.json'
        run('xcrun', 'devicectl', 'list', 'devices', '-j', str(listing),
            capture=True)
        devices = json.loads(listing.read_text())['result']['devices']
    return any(
        device.get('hardwareProperties', {}).get('udid') == device_udid
        and device.get('connectionProperties', {}).get('pairingState') == 'paired'
        and device.get('deviceProperties', {}).get('bootState') == 'booted'
        for device in devices
    )


def ensure_api_runtime():
    try:
        import jwt  # noqa: F401
        import requests  # noqa: F401
        return
    except ImportError:
        if os.environ.get('LITTLELOG_IOS_VENV') == '1':
            raise RuntimeError('Could not load the local Apple API packages.')
    python = ROOT / '.venv-ios-dev' / 'bin' / 'python'
    if not python.exists():
        venv.EnvBuilder(with_pip=True).create(ROOT / '.venv-ios-dev')
    ready = subprocess.run(
        [str(python), '-c', 'import jwt, requests'],
        capture_output=True,
    ).returncode == 0
    if not ready:
        run(str(python), '-m', 'pip', 'install', '--quiet',
            'PyJWT[crypto]==2.10.1', 'requests==2.32.5')
    os.environ['LITTLELOG_IOS_VENV'] = '1'
    os.execv(str(python), [str(python), __file__, *sys.argv[1:]])


def refresh_profiles(config, missing):
    ensure_api_runtime()
    import jwt
    import requests

    key_file = Path(config['api_key_file']).expanduser()
    if not key_file.is_file():
        raise RuntimeError('The configured Apple API key file is unavailable.')
    now = int(datetime.now(timezone.utc).timestamp())
    token = jwt.encode(
        {'iss': config['issuer_id'], 'iat': now, 'exp': now + 1100,
         'aud': 'appstoreconnect-v1'},
        key_file.read_text(), algorithm='ES256',
        headers={'kid': config['key_id'], 'typ': 'JWT'},
    )
    session = requests.Session()
    session.headers.update({'Authorization': f'Bearer {token}'})

    def api(method, path, body=None):
        response = session.request(
            method, 'https://api.appstoreconnect.apple.com' + path,
            json=body, timeout=60,
        )
        if not response.ok:
            raise RuntimeError(f'Apple provisioning request failed ({response.status_code}).')
        return response.json() if response.content else {}

    certificates = api('GET', '/v1/certificates?limit=200')['data']
    certificate = next((item for item in certificates
        if hashlib.sha1(base64.b64decode(
            item['attributes']['certificateContent'])).hexdigest().upper()
            == config['certificate_sha1']), None)
    if certificate is None:
        raise RuntimeError('The configured development certificate is no longer active.')

    devices = api('GET', '/v1/devices?limit=200')['data']
    device = next((item for item in devices
                   if item['attributes'].get('udid') == config['device_udid']), None)
    if device is None:
        device = api('POST', '/v1/devices', {'data': {
            'type': 'devices', 'attributes': {
                'name': 'Krupa iPhone', 'platform': 'IOS',
                'udid': config['device_udid'],
            },
        }})['data']

    identifiers = ','.join(missing)
    bundle_ids = api('GET', f'/v1/bundleIds?filter[identifier]={identifiers}&limit=200')['data']
    bundle_ids = {item['attributes']['identifier']: item['id'] for item in bundle_ids}
    profiles = api('GET', '/v1/profiles?filter[profileType]=IOS_APP_DEVELOPMENT&limit=200')['data']
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    for identifier, name in missing.items():
        if identifier not in bundle_ids:
            raise RuntimeError(f'Apple does not have the {identifier} bundle ID.')
        existing = next((item for item in profiles
                         if item['attributes'].get('name') == name), None)
        if existing is not None:
            api('DELETE', f"/v1/profiles/{existing['id']}")
        created = api('POST', '/v1/profiles', {'data': {
            'type': 'profiles',
            'attributes': {'name': name, 'profileType': 'IOS_APP_DEVELOPMENT'},
            'relationships': {
                'bundleId': {'data': {'type': 'bundleIds',
                                      'id': bundle_ids[identifier]}},
                'certificates': {'data': [{'type': 'certificates',
                                           'id': certificate['id']}]},
                'devices': {'data': [{'type': 'devices', 'id': device['id']}]},
            },
        }})['data']
        destination = PROFILE_DIR / f"{created['attributes']['uuid']}.mobileprovision"
        destination.write_bytes(base64.b64decode(
            created['attributes']['profileContent']))
        print(f'Refreshed {name} through {created["attributes"]["expirationDate"]}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=['install', 'build', 'check'],
                        default='install')
    args = parser.parse_args()
    if args.action != 'check':
        require_release_baseline()
    if not CONFIG.is_file():
        raise RuntimeError('Missing local config/ios_dev.local.json.')
    config = json.loads(CONFIG.read_text())
    identity = run('security', 'find-identity', '-v', '-p', 'codesigning',
                   capture=True).stdout
    if config['certificate_sha1'] not in identity:
        raise RuntimeError('The configured Apple development certificate is not valid in Keychain.')
    missing = missing_profiles(config)
    if missing:
        print('Refreshing development provisioning profiles...')
        refresh_profiles(config, missing)
        missing = missing_profiles(config)
        if missing:
            raise RuntimeError('Apple profiles could not be verified locally.')
    print('Development profiles are ready; Xcode sign-in is not needed.')
    if args.action == 'check':
        return

    if args.action == 'install' and not phone_connected(config['device_udid']):
        raise RuntimeError('The configured iPhone is paired but currently unavailable. '
                           'Connect or wake it, then rerun install.')

    google_config = require_google_config()
    run('flutter', 'build', 'ios', '--release', '--no-pub', GOOGLE_DEFINES)
    app = ROOT / 'build/ios/iphoneos/Runner.app'
    info = verify_google_build(app, google_config)
    if args.action == 'build':
        print(f"Verified Google-enabled Little Log {info['CFBundleShortVersionString']} "
              f"({info['CFBundleVersion']}) for iPhone.")
        return
    run('xcrun', 'devicectl', 'device', 'install', 'app', '--device',
        config['device_udid'], str(app))
    listing = run('xcrun', 'devicectl', 'device', 'info', 'apps', '--device',
                  config['device_udid'], '--bundle-id',
                  'app.littlelog.littleLog', capture=True).stdout
    if (info['CFBundleShortVersionString'] not in listing
            or info['CFBundleVersion'] not in listing):
        raise RuntimeError('The installed app version could not be verified.')
    run('xcrun', 'devicectl', 'device', 'process', 'launch', '--device',
        config['device_udid'], 'app.littlelog.littleLog')
    print(f"Installed Little Log {info['CFBundleShortVersionString']} "
          f"({info['CFBundleVersion']}) and launched it on the configured iPhone.")


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f'iPhone install failed: {exc}', file=sys.stderr)
        sys.exit(1)
