"""Small Android emulator acceptance harness; act on freshly observed UI nodes."""
import argparse
import os
import shutil
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ADB = shutil.which('adb') or '/opt/homebrew/share/android-commandlinetools/platform-tools/adb'
SERIAL = os.environ.get('ANDROID_SERIAL', 'emulator-5554')
if not SERIAL.startswith('emulator-'): raise SystemExit('This harness is restricted to emulators')

def adb(*args):
    return subprocess.check_output([ADB, '-s', SERIAL, *args], text=True)

def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/qa-window.xml')
    return list(ET.fromstring(adb('shell', 'cat', '/sdcard/qa-window.xml')).iter('node'))

def dump():
    for n in nodes():
        a=n.attrib
        label = a.get('text') or a.get('content-desc')
        if label or a.get('class') == 'android.widget.EditText':
            print(json.dumps({'label': '[password]' if a.get('password')=='true' else label,
                'class': a.get('class'), 'bounds': a.get('bounds'), 'id': a.get('resource-id'), 'clickable':a.get('clickable')}))

if __name__ == '__main__':
    p=argparse.ArgumentParser(); p.add_argument('action', choices=['dump','tap','tap-point','text','replace','back','scroll']); p.add_argument('value', nargs='?'); a=p.parse_args()
    if a.action=='tap':
        value, sep, index = a.value.partition('#')
        matches=[n for n in nodes() if value in (n.get('text'),n.get('content-desc'),n.get('resource-id'),n.get('class'))]
        if sep: matches=matches[int(index):int(index)+1]
        if len(matches)!=1: raise SystemExit(f'Expected one exact node, found {len(matches)}')
        x1,y1,x2,y2=map(int,re.findall(r'\d+',matches[0].get('bounds')))
        adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
    elif a.action=='tap-point':
        # Google's picker exposes only its WebView root to UIAutomator here.
        # Use a point read from a fresh emulator screenshot for that surface.
        if not a.value or not re.fullmatch(r'\d+,\d+',a.value): raise SystemExit('Expected x,y')
        x,y=map(int,a.value.split(','))
        size=adb('shell','wm','size')
        width,height=map(int,re.search(r'(\d+)x(\d+)',size).groups())
        if not (0 <= x < width and 0 <= y < height): raise SystemExit('Point outside emulator display')
        adb('shell','input','tap',str(x),str(y))
    elif a.action in ('text','replace'):
        if a.action=='replace':
            focused=[n for n in nodes() if n.get('focused')=='true' and n.get('class')=='android.widget.EditText']
            if len(focused)!=1 or focused[0].get('password')=='true': raise SystemExit('Expected one focused non-password field')
            adb('shell','input','keyevent','KEYCODE_MOVE_END')
            length=len(focused[0].get('text',''))
            if length: adb('shell','input','keyevent',*(['KEYCODE_DEL']*length))
        # Synthetic QA text only. Never pass credentials to this harness.
        if not re.fullmatch(r'[A-Za-z0-9 ._-]+',a.value): raise SystemExit('Use simple synthetic QA text')
        adb('shell','input','text',a.value.replace(' ','%s'))
    elif a.action=='scroll':
        candidates=[n for n in nodes() if n.get('scrollable')=='true']
        if not candidates: raise SystemExit('No scroll container')
        x1,y1,x2,y2=map(int,re.findall(r'\d+',candidates[-1].get('bounds')))
        x=(x1+x2)//2; top=y1+(y2-y1)//4; bottom=y1+3*(y2-y1)//4
        adb('shell','input','swipe',str(x),str(bottom if a.value!='up' else top),str(x),str(top if a.value!='up' else bottom),'400')
    elif a.action=='back': adb('shell','input','keyevent','KEYCODE_BACK')
    dump()
