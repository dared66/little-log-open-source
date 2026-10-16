"""Run synthetic native harnesses and route Android profiling to host DDS."""
import argparse
import json
from pathlib import Path
import re
import subprocess
from android_display import inspect_display

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('platform', choices=['android', 'ios'])
parser.add_argument('harness', nargs='?', default='usability_validation',
                    choices=['branch_validation', 'assistant_features', 'usability_validation', 'heavy_validation', 'performance',
                             'native_density_layout', 'native_surface_validation', 'android_layout_review', 'store_screenshots'])
parser.add_argument('--device', required=True,
                    help='Explicit disposable QA emulator/simulator; never the development device.')
parser.add_argument('--test-name', help='Run only tests containing this literal name.')
parser.add_argument('--layout-review-phase', choices=['full', 'extras', 'pages', 'recovery'], default='full')
parser.add_argument('--capture-folder', type=Path)
parser.add_argument('--allow-display-overrides', action='store_true',
                    help='Explicitly test intentional emulator resolution/density overrides.')
args = parser.parse_args()
device = args.device
protected_devices = {'emulator-5580', 'D0317E7F-CC69-4B2D-AD9E-65B9897DF9D0'}
ios_config = ROOT / 'config' / 'ios_dev.local.json'
if ios_config.is_file():
    configured_device = json.loads(ios_config.read_text()).get('simulator_udid')
    if configured_device:
        protected_devices.add(configured_device)
if device in protected_devices:
    raise SystemExit('This is a protected development device. Native tests replace the app '
                     'and can erase its data during cleanup. Use a separate disposable QA device.')
adb = ['adb', '-s', device]
display = None
if args.platform == 'android':
    if not device.startswith('emulator-'):
        raise SystemExit('Use an Android emulator.')
    if subprocess.check_output(adb + ['shell', 'getprop', 'ro.kernel.qemu'],
                               text=True).strip() != '1':
        raise SystemExit('Use an Android emulator.')
    display = inspect_display(adb)
    print('ANDROID_DISPLAY_METRICS ' + json.dumps(display), flush=True)
    if display['has_overrides'] and not args.allow_display_overrides:
        raise SystemExit('Android display size/density is overridden. Restore native emulator '
                         'settings, or use --allow-display-overrides for intentional scaling QA.')
else:
    inventory = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))
    if not any(item['udid'] == device for group in inventory['devices'].values()
               for item in group):
        raise SystemExit('Use an available iOS simulator.')

command = ['flutter', 'test', '--no-uninstall', '--reporter', 'expanded',
           '-d', device, '--dart-define-from-file=config/google.local.json',
           f'integration_test/{args.harness}_test.dart']
if args.test_name:
    command[2:2] = ['--plain-name', args.test_name]
if display is not None:
    command.insert(-1, f'--dart-define=NATIVE_QA_EXPECTED_DPR={display["device_pixel_ratio"]}')
if args.harness == 'android_layout_review':
    command.insert(-1, f'--dart-define=LAYOUT_REVIEW_PHASE={args.layout_review_phase}')
ports = set()
captures = []
capture_folder = args.capture_folder or ROOT.parent / 'output/android-layout-review'
if args.harness == 'android_layout_review':
    if args.platform != 'android':
        raise SystemExit('The Android layout review requires an Android emulator.')
    capture_folder.mkdir(parents=True, exist_ok=True)
process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
try:
    for line in process.stdout:
        print(line, end='', flush=True)
        if line.startswith('ANDROID_LAYOUT_CHECKPOINT '):
            checkpoint = json.loads(line.removeprefix('ANDROID_LAYOUT_CHECKPOINT '))
            metadata = checkpoint['metadata']
            name = metadata['file']
            ready = checkpoint['ready']
            if Path(name).name != name or not ready.startswith(
                    '/storage/emulated/0/Android/data/app.littlelog.little_log/files/qa-android-layout/'):
                raise RuntimeError('Unexpected capture path.')
            pixels = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=20)
            if not pixels.startswith(b'\x89PNG\r\n\x1a\n'):
                raise RuntimeError('The emulator did not return a PNG screenshot.')
            (capture_folder / name).write_bytes(pixels)
            captures.append(metadata)
            (capture_folder / 'manifest.json').write_text(json.dumps(captures, indent=2) + '\n')
            subprocess.run(adb + ['shell', 'touch', ready], check=True,
                           capture_output=True, timeout=10)
        match = re.search(r'ANDROID_PROFILER_PORT: (\d+)', line)
        if match and args.platform == 'android':
            port = match[1]
            subprocess.run(adb + ['reverse', f'tcp:{port}', f'tcp:{port}'],
                           check=True, capture_output=True)
            ports.add(port)
            print('Android profiler route ready.', flush=True)
    result = process.wait()
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=15)
    for port in ports:
        subprocess.run(adb + ['reverse', '--remove', f'tcp:{port}'],
                       capture_output=True)
raise SystemExit(result)
