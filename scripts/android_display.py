"""Record native Android display settings before visual acceptance tests."""
import re
import subprocess


def display_metrics(size_output, density_output):
    def value(output, label, pattern):
        match = re.search(rf'^{label}:\s*({pattern})\s*$', output, re.MULTILINE)
        return match.group(1) if match else None

    physical_size = value(size_output, 'Physical size', r'\d+x\d+')
    physical_density = value(density_output, 'Physical density', r'\d+')
    if physical_size is None or physical_density is None:
        raise ValueError('Android did not report physical size and density.')
    override_size = value(size_output, 'Override size', r'\d+x\d+')
    override_density = value(density_output, 'Override density', r'\d+')
    width, height = map(int, (override_size or physical_size).split('x'))
    density = int(override_density or physical_density)
    if width <= 0 or height <= 0 or density <= 0:
        raise ValueError('Android display dimensions and density must be positive.')
    return {
        'physical_size': physical_size,
        'physical_density_dpi': int(physical_density),
        'override_size': override_size,
        'override_density_dpi': int(override_density) if override_density else None,
        'device_pixel_ratio': density / 160,
        'logical_portrait_size': [width * 160 / density, height * 160 / density],
        'has_overrides': override_size is not None or override_density is not None,
    }


def inspect_display(adb):
    return display_metrics(
        subprocess.check_output(adb + ['shell', 'wm', 'size'], text=True),
        subprocess.check_output(adb + ['shell', 'wm', 'density'], text=True),
    )
