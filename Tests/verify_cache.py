#!/usr/bin/env python3
"""Check that prepared labels follow DOM mutations, page scrolling, and navigation."""
import time
import json
from pathlib import Path
import verify as v

bundle = 'app.zen-browser.zen'
gate = Path(__file__).resolve().parent / '_keyrow-fixture-state.json'
run = str(time.time_ns())
def signal(ready):
    temporary = gate.with_suffix('.tmp')
    temporary.write_text(json.dumps({'run': run, 'ready': ready}))
    temporary.replace(gate)
try:
    signal(False)
    v.navigate(bundle, f'http://127.0.0.1:8765/browser-fixture.html?dynamic=1&run={run}', new_tab=True)
    end = time.monotonic() + 15
    while not any(n['role'] == 'AXWebArea' and run in n.get('AXURL', '') for n in v.inspect(bundle)):
        assert time.monotonic() < end, 'New fixture document did not load'
        time.sleep(.05)
    end = time.monotonic() + 8
    while True:
        info = v.activate(bundle)
        assert not any(t['title'] == 'Delayed control' for t in info['targets'])
        v.driver('key', 'Escape')
        if info.get('cache_hit'):
            break
        assert time.monotonic() < end, 'No prepared snapshot became available'
    # Change the page through its fixture server without a keyboard/mouse event.
    signal(True)
    v.expect(bundle, 'Delayed control')
    info = v.activate(bundle)
    match = next((t for t in info['targets'] if t['title'] == 'Delayed control'), None)
    assert match, 'Prepared labels missed a new control added without user input'
    v.driver('hint', match['label']); v.wait_mode('idle')
    v.expect(bundle, 'Delayed clicked')
    v.activate(bundle); v.driver('key', 'Escape')
    signal(False)
    end = time.monotonic() + 8
    while 'Delayed clicked' in v.node_text(v.inspect(bundle)):
        assert time.monotonic() < end, 'Fixture did not remove its control'
        time.sleep(.1)
    info = v.activate(bundle)
    assert not any(t['title'].startswith('Delayed') for t in info['targets']), 'Prepared labels retained a removed control'
    v.driver('key', 'Escape')
    v.activate(bundle, 'scroll'); v.driver('key', '0'); v.driver('key', 'j', 'hold', '.6')
    v.driver('key', 'Escape'); v.wait_mode('idle')
    info = v.activate(bundle)
    assert not any(t['title'] == 'Count click' for t in info['targets']), 'Prepared labels retained an offscreen control after scrolling'
    v.driver('key', 'Escape')
    v.navigate(bundle, 'http://127.0.0.1:8765/browser-fixture.html?navigation=1')
    v.expect(bundle, 'Clicks: 0')
    v.hint(bundle, 'Count click'); v.expect(bundle, 'Clicks: 1')
    v.record({'browser': 'Zen', 'scenario': 'prepared-label invalidation', 'status': 'PASS',
              'automatic_dom_change': True, 'removed_control': True, 'scroll_position': True, 'navigation': True})
finally:
    gate.unlink(missing_ok=True)
    if v.STATE.exists() and v.state()['mode'] != 'idle':
        v.driver('key', 'Escape')
