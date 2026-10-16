"""Boot the configured iOS simulator and run or install Little Log."""

import argparse
import json
import plistlib
import struct
from pathlib import Path
import subprocess
import sys
from ios_build_config import GOOGLE_DEFINES, require_google_config, verify_google_build


ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'config' / 'ios_dev.local.json'
BUNDLE_ID = 'app.littlelog.littleLog'


def run(*command, capture=False):
    return subprocess.run(command, check=True, text=True, cwd=ROOT,
                          capture_output=capture)


def verify_keychain_signing(app):
    """Reject simulator apps that launch but cannot store Google credentials."""
    run('codesign', '--verify', '--strict', str(app))
    # Xcode embeds simulator entitlements in Mach-O, not the signature's plist.
    binary = (app / 'Runner').read_bytes()
    try:
        if struct.unpack_from('<I', binary)[0] != 0xfeedfacf:
            raise ValueError('Expected the configured arm64 simulator executable.')
        command_offset = 32
        entitlements = {}
        for _ in range(struct.unpack_from('<I', binary, 16)[0]):
            command, size = struct.unpack_from('<II', binary, command_offset)
            if size < 8:
                raise ValueError('Invalid Mach-O load command.')
            if command == 0x19:  # LC_SEGMENT_64
                for section in range(struct.unpack_from('<I', binary, command_offset + 64)[0]):
                    offset = command_offset + 72 + section * 80
                    name, segment, _, length, start = struct.unpack_from('<16s16sQQI', binary, offset)
                    if name.rstrip(b'\0') == b'__entitlements' and segment.rstrip(b'\0') == b'__TEXT':
                        entitlements = plistlib.loads(binary[start:start + length])
            command_offset += size
    except (ValueError, struct.error, plistlib.InvalidFileException) as exc:
        raise RuntimeError('Simulator app is missing its Keychain signing entitlements.') from exc
    identity = entitlements.get('application-identifier', '')
    if (not identity.endswith('.' + BUNDLE_ID)
            or identity not in entitlements.get('keychain-access-groups', [])):
        raise RuntimeError('Simulator app is missing its own Keychain identity; Google sign-in cannot finish.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=['install', 'run'],
                        default='install')
    args = parser.parse_args()
    if not CONFIG.is_file():
        raise RuntimeError('Missing local config/ios_dev.local.json.')
    device_id = json.loads(CONFIG.read_text()).get('simulator_udid')
    if not device_id:
        raise RuntimeError('Set simulator_udid in config/ios_dev.local.json.')

    output = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available',
                            '-j', capture=True).stdout)
    devices = [device for group in output['devices'].values()
               for device in group if device['udid'] == device_id]
    if not devices:
        raise RuntimeError('The configured iOS simulator is unavailable.')
    if devices[0]['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', device_id)
    run('xcrun', 'simctl', 'bootstatus', device_id, '-b')
    google_config = require_google_config()

    if args.action == 'run':
        print(f'Running Little Log on {devices[0]["name"]}; Flutter hot reload is available.',
              flush=True)
        run('flutter', 'run', '--debug', '-d', device_id, '--no-pub',
            GOOGLE_DEFINES)
        return

    run('flutter', 'build', 'ios', '--simulator', '--no-pub',
        GOOGLE_DEFINES)
    app = ROOT / 'build/ios/iphonesimulator/Runner.app'
    info = verify_google_build(app, google_config, debug=True)
    verify_keychain_signing(app)
    run('xcrun', 'simctl', 'install', device_id, str(app))
    run('xcrun', 'simctl', 'launch', device_id, BUNDLE_ID)
    container = run('xcrun', 'simctl', 'get_app_container', device_id,
                    BUNDLE_ID, 'app', capture=True).stdout.strip()
    installed = plistlib.loads((Path(container) / 'Info.plist').read_bytes())
    if (installed['CFBundleShortVersionString'] != info['CFBundleShortVersionString']
            or installed['CFBundleVersion'] != info['CFBundleVersion']):
        raise RuntimeError('The simulator app version could not be verified.')
    print(f'Installed and launched Little Log {info["CFBundleShortVersionString"]} '
          f'({info["CFBundleVersion"]}) on {devices[0]["name"]}.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f'iOS simulator setup failed: {exc}', file=sys.stderr)
        sys.exit(1)
