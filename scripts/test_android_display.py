import unittest
import contextlib
import io
from pathlib import Path
import runpy
import subprocess
from unittest.mock import patch
from android_display import display_metrics


class AndroidDisplayTest(unittest.TestCase):
    def test_native_phone_density_reports_real_logical_geometry(self):
        metrics = display_metrics('Physical size: 1080x2400\n', 'Physical density: 420\n')
        self.assertFalse(metrics['has_overrides'])
        self.assertEqual(metrics['device_pixel_ratio'], 2.625)
        self.assertAlmostEqual(metrics['logical_portrait_size'][0], 411.428571, places=5)

    def test_low_density_override_cannot_masquerade_as_native_phone(self):
        metrics = display_metrics('Physical size: 1080x2400\n',
                                  'Physical density: 420\nOverride density: 280\n')
        self.assertTrue(metrics['has_overrides'])
        self.assertEqual(metrics['physical_density_dpi'], 420)
        self.assertEqual(metrics['override_density_dpi'], 280)
        self.assertEqual(metrics['device_pixel_ratio'], 1.75)
        self.assertAlmostEqual(metrics['logical_portrait_size'][0], 617.142857, places=5)

    def test_resolution_override_is_recorded_separately(self):
        metrics = display_metrics('Physical size: 1080x2400\nOverride size: 720x1280\n',
                                  'Physical density: 420\nOverride density: 320\n')
        self.assertTrue(metrics['has_overrides'])
        self.assertEqual(metrics['physical_size'], '1080x2400')
        self.assertEqual(metrics['logical_portrait_size'], [360.0, 640.0])

    def test_missing_or_invalid_geometry_is_rejected(self):
        for size, density in [('unavailable', 'Physical density: 420'),
                              ('Physical size: 1080x2400', 'Physical density: 0')]:
            with self.assertRaises(ValueError):
                display_metrics(size, density)

    def run_guard(self, allow_overrides=False):
        def adb_output(command, **kwargs):
            if command[-2:] == ['getprop', 'ro.kernel.qemu']:
                return '1\n'
            if command[-2:] == ['wm', 'size']:
                return 'Physical size: 1080x2400\n'
            if command[-2:] == ['wm', 'density']:
                return 'Physical density: 420\nOverride density: 280\n'
            raise AssertionError(f'Unexpected device command: {command}')

        arguments = ['run_native_tests.py', 'android', '--device', 'emulator-5566']
        if allow_overrides:
            arguments.append('--allow-display-overrides')
        with patch('sys.argv', arguments), \
             patch('subprocess.check_output', side_effect=adb_output), \
             patch('subprocess.Popen') as launch, \
             contextlib.redirect_stdout(io.StringIO()):
            launch.return_value.stdout = []
            launch.return_value.wait.return_value = 0
            launch.return_value.poll.return_value = 0
            with self.assertRaises(SystemExit) as stopped:
                runpy.run_path(str(Path(__file__).with_name('run_native_tests.py')), run_name='__main__')
        return stopped.exception, launch

    def test_normal_visual_qa_stops_before_launch_on_density_override(self):
        stopped, launch = self.run_guard()
        self.assertIn('display size/density is overridden', str(stopped))
        launch.assert_not_called()

    def test_intentional_scaling_qa_records_and_passes_the_effective_density(self):
        stopped, launch = self.run_guard(allow_overrides=True)
        self.assertEqual(stopped.code, 0)
        self.assertIn('--dart-define=NATIVE_QA_EXPECTED_DPR=1.75', launch.call_args.args[0])
        self.assertIn('--no-uninstall', launch.call_args.args[0])

    def test_native_tests_require_an_explicit_qa_device(self):
        with patch('sys.argv', ['run_native_tests.py', 'ios']), \
                patch('subprocess.Popen') as launch, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as stopped:
                runpy.run_path(str(Path(__file__).with_name('run_native_tests.py')), run_name='__main__')
        self.assertEqual(stopped.exception.code, 2)
        launch.assert_not_called()

    def test_shared_development_devices_are_rejected_before_device_access(self):
        for platform, device in [
            ('android', 'emulator-5580'),
            ('ios', 'D0317E7F-CC69-4B2D-AD9E-65B9897DF9D0'),
        ]:
            with self.subTest(platform=platform), \
                    patch('sys.argv', ['run_native_tests.py', platform, '--device', device]), \
                    patch('subprocess.check_output') as inspect_device, \
                    patch('subprocess.Popen') as launch:
                with self.assertRaisesRegex(SystemExit, 'protected development device'):
                    runpy.run_path(str(Path(__file__).with_name('run_native_tests.py')), run_name='__main__')
                inspect_device.assert_not_called()
                launch.assert_not_called()

    def test_native_ui_runners_reject_the_shared_review_device(self):
        root = Path(__file__).resolve().parent.parent
        for name in ['run_android_voice_actions.sh', 'run_android_import_picker.sh']:
            with self.subTest(runner=name):
                result = subprocess.run(['/bin/bash', str(root / 'tool' / name), 'emulator-5580'],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('shared review emulator is protected', result.stderr)

    def test_native_ui_runners_have_no_implicit_device(self):
        root = Path(__file__).resolve().parent.parent
        for name in ['run_android_voice_actions.sh', 'run_android_import_picker.sh']:
            with self.subTest(runner=name):
                result = subprocess.run(['/bin/bash', str(root / 'tool' / name)],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Pass a disposable QA emulator ID explicitly', result.stderr)


if __name__ == '__main__':
    unittest.main()
