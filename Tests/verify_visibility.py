#!/usr/bin/env python3
"""Regression for click-through system windows hiding every accessible control.

Open KeyRow's practice window and enable diagnostic output before running.
This uses the current desktop window stack without dismissing system overlays.
"""
import argparse
import re
import subprocess
import verify as v

parser = argparse.ArgumentParser()
parser.add_argument('--cover', help='Path to the compiled occlusion-fixture executable')
args = parser.parse_args()
cover = None
try:
    v.driver('focus', 'local.keyrow.app')
    before = v.inspect('local.keyrow.app')
    count = int(re.search(r'Clicks: (\d+)', v.node_text(before)).group(1))
    info = v.activate('local.keyrow.app')
    buttons = [t for t in info['targets'] if t['title'] == 'Count click']
    assert buttons, 'Visible practice button was removed by the window-occlusion check'
    v.driver('hint', buttons[0]['label'])
    v.wait_mode('idle')
    v.expect('local.keyrow.app', f'Clicks: {count + 1}')
    if args.cover:
        button = next(n for n in before if n.get('AXTitle') == 'Count click' or n.get('AXDescription') == 'Count click')
        x, y, width, height = button['frame']
        cover = subprocess.Popen([args.cover, str(x - 10), str(y - 10), str(width + 20), str(height + 20)], stdout=subprocess.PIPE, text=True)
        assert cover.stdout.readline().strip() == 'ready', 'Cover fixture did not start'
        info = v.activate('local.keyrow.app')
        assert not any(t['title'] == 'Count click' for t in info['targets']), 'A control covered by a real floating window was labelled'
        v.driver('key', 'Escape')
        cover.terminate()
        cover.wait(timeout=5)
        cover = None
        info = v.activate('local.keyrow.app')
        assert any(t['title'] == 'Count click' for t in info['targets']), 'Control did not return after removing the covering window'
        v.driver('key', 'Escape')
    v.record({'scenario': 'click-through overlay visibility', 'status': 'PASS',
              'native_button_click': True, 'real_window_occlusion': bool(args.cover)})
finally:
    if cover is not None:
        cover.terminate()
        cover.wait(timeout=5)
    if v.STATE.exists() and v.state()['mode'] != 'idle':
        v.driver('key', 'Escape')
