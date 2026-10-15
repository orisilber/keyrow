#!/usr/bin/env python3
"""Use labels to focus Zen's address bar and select a browser tab."""
import time
import verify as v

bundle = 'app.zen-browser.zen'
def document(expected):
    end = time.monotonic() + 20
    while True:
        nodes = v.inspect(bundle)
        if any(n['role'] == 'AXWebArea' and expected in n.get('AXURL', '') for n in nodes):
            return nodes
        assert time.monotonic() < end, 'Browser did not show the expected document'
        time.sleep(.1)
try:
    run = str(time.time_ns())
    v.navigate(bundle, f'http://127.0.0.1:8765/browser-fixture.html?controls={run}', new_tab=True)
    nodes = document(run)
    v.hint(bundle, 'Count click'); v.expect(bundle, 'Clicks: 1')
    info = v.activate(bundle)
    reload = next(t for t in info['targets'] if t['role'] == 'AXButton' and t['title'] == 'Reload')
    v.driver('hint', reload['label']); v.wait_mode('idle')
    v.expect(bundle, 'Clicks: 0')
    info = v.activate(bundle)
    menu = next(t for t in info['targets'] if t['role'] == 'AXMenuBarItem' and t['title'] == 'File')
    v.driver('hint', menu['label']); v.wait_mode('idle')
    v.driver('hotkey', 'click'); info = v.wait_mode('clicking')
    assert any(t['role'] == 'AXMenuItem' and t['title'].startswith('New Window') for t in info['targets']), 'File menu did not expose its controls'
    v.driver('key', 'Escape'); v.wait_mode('idle'); v.driver('key', 'Escape')
    v.hint(bundle, 'Count click'); v.expect(bundle, 'Clicks: 1')
    web = next(n['frame'] for n in nodes if n['role'] == 'AXWebArea' and 'frame' in n)
    x, y, w, h = web
    info = v.activate(bundle)
    assert any(t['role'] == 'AXMenuBarItem' for t in info['targets'])
    assert any(t['role'] == 'AXButton' and t['title'] in ['Reload', 'Stop', 'Zen', 'Compact Mode'] for t in info['targets']), 'Browser toolbar buttons were excluded'
    address = next(t for t in info['targets'] if t['role'] == 'AXComboBox' and not (x <= t['frame'][0] + t['frame'][2] / 2 <= x + w and y <= t['frame'][1] + t['frame'][3] / 2 <= y + h))
    v.driver('hint', address['label']); v.wait_mode('idle')
    v.driver('key', 'a', 'cmd'); v.driver('text', 'https://www.wikipedia.org/'); v.driver('key', 'Return')
    document('www.wikipedia.org')
    v.navigate(bundle, f'http://127.0.0.1:8765/browser-fixture.html?controls-tab={run}', new_tab=True)
    document(run)
    info = v.activate(bundle)
    tab = next(t for t in info['targets'] if t['role'] in ['AXTab', 'AXRadioButton'] and t['title'] == 'Wikipedia')
    v.driver('hint', tab['label']); v.wait_mode('idle')
    document('www.wikipedia.org')
    v.driver('key', 'w', 'cmd')
    v.record({'browser': 'Zen', 'scenario': 'browser controls', 'status': 'PASS',
              'address_bar_label_and_navigation': True, 'tab_label_and_selection': True,
              'toolbar_reload_reset_counter': True, 'file_menu_opened_and_items_labelled': True, 'toolbar_and_menu_labels_present': True})
finally:
    if v.STATE.exists() and v.state()['mode'] != 'idle':
        v.driver('key', 'Escape')
