#!/usr/bin/env python3
"""Check all connected HID mappings and actual modifier delivery in a browser."""
import argparse
import re
import subprocess
import verify as v

parser = argparse.ArgumentParser()
parser.add_argument('--browser', default='app.zen-browser.zen')
parser.add_argument('--name', default='Zen')
args = parser.parse_args()
text = subprocess.check_output(['hidutil', 'property', '--matching', 'keyboard', '--get', 'UserKeyMapping'], text=True)
devices = len(re.findall(r'(?m)^[0-9a-fA-F]+\s+UserKeyMapping\s+', text))
caps = []
for block in re.findall(r'\{[^{}]*\}', text):
    values = {k: int(n) for k, n in re.findall(r'HIDKeyboardModifierMapping(Src|Dst)\s*=\s*(\d+)', block)}
    if values.get('Src') == 0x700000039:
        caps.append(values.get('Dst'))
assert devices > 0 and len(caps) == devices and all(n == 0x70000006d for n in caps), 'A connected keyboard is missing the Caps Lock to F18 mapping'
try:
    v.navigate(args.browser, 'http://127.0.0.1:8765/browser-fixture.html')
    v.expect(args.browser, 'Hyper chords: 0')
    v.hint(args.browser, 'Practice text')
    v.driver('hyper-chord')
    v.expect(args.browser, 'Hyper chords: 1 · Released keys: 1 · Stuck modifiers: 0')
    v.record({'browser': args.name, 'scenario': 'Hyper delivery and release', 'status': 'PASS',
              'keyboards_mapped': devices, 'four_modifiers_delivered': True, 'released_without_sticking': True})
finally:
    if v.STATE.exists() and v.state()['mode'] != 'idle':
        v.driver('key', 'Escape')
