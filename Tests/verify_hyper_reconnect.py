#!/usr/bin/env python3
"""Watch a real keyboard reconnect and physical Caps Lock hold/release.

Start with Hyper enabled and diagnostics running. Turn the external keyboard
off for three seconds and back on, then hold Caps Lock for two seconds and
release it. No keyboard events are synthesized by this check.
"""
import argparse
import re
import subprocess
import time
import verify as v

parser = argparse.ArgumentParser()
parser.add_argument('--timeout', type=float, default=180)
args = parser.parse_args()

def mappings():
    output = subprocess.check_output(['hidutil', 'property', '--matching', 'keyboard', '--get', 'UserKeyMapping'], text=True)
    rows = list(re.finditer(r'(?m)^([0-9a-fA-F]+)\s+UserKeyMapping\s+', output))
    found = {}
    for i, match in enumerate(rows):
        block = output[match.end():rows[i + 1].start() if i + 1 < len(rows) else len(output)]
        caps = []
        for entry in re.findall(r'\{[^{}]*\}', block):
            values = {k: int(n) for k, n in re.findall(r'HIDKeyboardModifierMapping(Src|Dst)\s*=\s*(\d+)', entry)}
            if values.get('Src') == 0x700000039:
                caps.append(values.get('Dst'))
        found[match[1]] = caps
    return found

initial = mappings()
assert initial and all(value == [0x70000006d] for value in initial.values()), 'Begin with all connected keyboards mapped'
before = v.state()
assert before.get('hyper_enabled') and not before.get('hyper_error'), 'Begin with Hyper running without an error'
presses = before['hyper_presses']
print('READY: reconnect the external keyboard, then hold and release physical Caps Lock.', flush=True)
end = time.monotonic() + args.timeout
saw_disconnect = False
stable_since = None
while time.monotonic() < end:
    current = mappings()
    saw_disconnect |= not set(initial).issubset(current)
    state = v.state()
    reconnected = (saw_disconnect or bool(set(current) - set(initial))) and len(current) >= len(initial)
    restored = reconnected and all(value == [0x70000006d] for value in current.values()) and state.get('hyper_enabled') and not state.get('hyper_error')
    physical = state['hyper_presses'] > presses and not state['hyper_held']
    if restored and physical:
        if stable_since is None:
            stable_since = time.monotonic()
        if time.monotonic() - stable_since >= 1:
            v.record({'scenario': 'Hyper reconnect and physical Caps Lock', 'status': 'PASS',
                      'keyboards_mapped': len(current), 'device_disconnect_observed': saw_disconnect,
                      'new_service_observed': bool(set(current) - set(initial)),
                      'physical_press_and_release': True, 'warning_cleared': True})
            break
    else:
        stable_since = None
    time.sleep(.1)
else:
    raise AssertionError('Reconnect and physical Caps Lock release were not verified before the timeout')
