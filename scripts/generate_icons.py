"""Export the approved Little Log artwork to platform icon sizes (Pillow)."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / 'assets/branding/little-log-mark.png').convert('RGBA')
paper = Image.new('RGBA', source.size, '#FAF8F4')
paper.alpha_composite(source)
master = paper.convert('RGB')
master.resize((1024, 1024), Image.Resampling.LANCZOS).save(
    ROOT / 'assets/branding/little-log-icon.png')

def export(path, size):
    master.resize((size, size), Image.Resampling.LANCZOS).save(path)

catalog = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((catalog / 'Contents.json').read_text())['images']:
    size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
    export(catalog / item['filename'], size)

for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96,
                      'xxhdpi': 144, 'xxxhdpi': 192}.items():
    export(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
for size in (192, 512):
    for prefix in ('Icon', 'Icon-maskable'):
        export(ROOT / f'web/icons/{prefix}-{size}.png', size)
export(ROOT / 'web/favicon.png', 32)
print('Exported iOS, Android, and web icons with an opaque warm-paper background.')
