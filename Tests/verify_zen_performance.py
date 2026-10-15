#!/usr/bin/env python3
"""Measure real shortcut-to-label-draw latency on YouTube in Zen, including browser controls."""
import argparse
import json
import math
import statistics
import time
import verify as v

parser = argparse.ArgumentParser()
parser.add_argument('--samples', type=int, default=20)
parser.add_argument('--current-tab', action='store_true')
args = parser.parse_args()
bundle = 'app.zen-browser.zen'
samples = []
try:
    if not args.current_tab:
        v.navigate(bundle, f'https://www.youtube.com/#keyrow-verification-{time.time_ns()}', new_tab=True)
    end = time.monotonic() + 40
    previous = None
    stable_since = 0
    while True:
        nodes = v.inspect(bundle)
        document = any(n['role'] == 'AXWebArea' and n.get('AXURL', '').startswith('https://www.youtube.com/') for n in nodes)
        videos = [n for n in nodes if n['role'] == 'AXLink' and '/watch?' in n.get('AXURL', '') and 'frame' in n and n['frame'][2] > 2 and n['frame'][3] > 2]
        key = tuple((n.get('AXURL'), tuple(n['frame'])) for n in videos)
        if document and len(videos) >= 3 and key == previous:
            if time.monotonic() - stable_since >= .4:
                break
        else:
            previous = key; stable_since = time.monotonic()
        assert time.monotonic() < end, 'YouTube video controls did not become ready'
        time.sleep(.1)
    # Foreground Zen once. Re-activating the application on every iteration
    # measures a different operation and can itself invalidate prepared controls.
    v.driver('focus', bundle)
    for _ in range(args.samples):
        if v.state()['mode'] != 'idle':
            v.driver('key', 'Escape'); v.wait_mode('idle')
        v.driver('hotkey', 'click')
        info = v.wait_mode('clicking')
        assert info.get('ready_ms') is not None, 'Build has no activation timing'
        roles = [t['role'] for t in info['targets']]
        assert 'AXMenuBarItem' in roles, 'Browser menu controls were excluded'
        assert 'AXComboBox' in roles, 'Address bar was excluded'
        assert 'AXRadioButton' in roles or 'AXTab' in roles, 'Browser tabs were excluded'
        assert 'AXLink' in roles and 'AXButton' in roles, 'Page controls are missing'
        assert not any(r in ['AXStaticText', 'AXGroup', 'AXToolbar'] for r in roles), 'Decorative or structural nodes received labels'
        samples.append({'ready_ms': info['ready_ms'], 'cache_hit': info.get('cache_hit', False), 'targets': len(roles), 'source_scan_ms': info.get('milliseconds'), 'phases': info.get('phases')})
        v.driver('key', 'Escape')
    values = sorted(s['ready_ms'] for s in samples)
    summary = {'browser': 'Zen', 'scenario': 'YouTube latency and browser controls', 'status': 'MEASURED',
               'samples': samples, 'median_ms': statistics.median(values),
               'p95_ms': values[math.ceil(len(values) * .95) - 1], 'max_ms': max(values),
               'browser_controls_included': True}
    (v.ROOT / 'work/zen-latency-samples.json').write_text(json.dumps(summary, indent=2))
    assert summary['median_ms'] < 50, f"Median activation took {summary['median_ms']:.1f} ms"
    assert summary['p95_ms'] < 100, f"p95 activation took {summary['p95_ms']:.1f} ms"
    summary['status'] = 'PASS'
    v.record(summary)
finally:
    if v.STATE.exists() and v.state()['mode'] != 'idle':
        v.driver('key', 'Escape')
