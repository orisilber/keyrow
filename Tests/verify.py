#!/usr/bin/env python3
"""Run KeyRow through its real global event listener. Requires the test Info.plist key."""
import json
import subprocess
import time
import re
import hashlib
import datetime
import shutil
import os
from pathlib import Path

ROOT = Path(os.environ.get('KEYROW_TEST_WORKSPACE', str(Path(__file__).resolve().parents[1] / ".verification")))
APP = ROOT / "outputs/KeyRow.app"
STATE = ROOT / "work/navigation-state.json"
LOG = ROOT / "work/verification-driver"
LOG.mkdir(parents=True, exist_ok=True)
(APP.parent).mkdir(parents=True, exist_ok=True)
sequence = 0
run_id = str(time.time_ns())

def driver(*args):
    global sequence
    sequence += 1
    out = LOG / f"{run_id}-{sequence:04d}.txt"
    err = LOG / f"{run_id}-{sequence:04d}.err"
    proc = subprocess.run(["open", "-n", "-g", "-W", "-a", str(APP), "--stdout", str(out), "--stderr", str(err), "--args", "--driver", *map(str,args)], capture_output=True,text=True,timeout=20)
    # LaunchServices can lose its wait registration when a tiny driver has already exited.
    if proc.returncode and "kevent() failed: No such process" not in proc.stderr:
        raise AssertionError(proc.stderr)
    text = out.read_text() if out.exists() else ""
    if "Driver requires" in text or "App not running" in text:
        raise AssertionError(text)
    return text

def state():
    return json.loads(STATE.read_text())

def wait_mode(mode):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if STATE.exists() and state()["mode"] == mode:
            return state()
        time.sleep(.05)
    raise AssertionError(f"Expected {mode}, got {state()['mode']}")

def inspect(bundle):
    return json.loads(driver("inspect",bundle))

def node_text(nodes):
    return "\n".join(str(value) for node in nodes for key,value in node.items() if key != "frame")

def expect(bundle, text):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        nodes = inspect(bundle)
        if text in node_text(nodes): return nodes
        time.sleep(.1)
    raise AssertionError(f"{bundle}: missing {text!r}")

def activate(bundle, mode="click"):
    if state()["mode"] != "idle": driver("key","Escape"); wait_mode("idle")
    driver("focus",bundle)
    driver("hotkey",mode)
    return wait_mode("clicking" if mode == "click" else "scrolling")

def hint(bundle,title, gesture="hint"):
    info = activate(bundle)
    candidates = [t for t in info["targets"] if t["title"] == title]
    if not candidates: raise AssertionError(f"No label for {title!r}; available: {[t['title'] for t in info['targets']]}")
    driver(gesture,candidates[0]["label"])
    wait_mode("idle")
    return info

def navigate(bundle,url,new_tab=False):
    driver("focus",bundle)
    if state()["mode"] != "idle": driver("key","Escape")
    if new_tab: driver("key","t","cmd")
    driver("key","l","cmd")
    driver("text",url)
    driver("key","Return")

def launch(name):
    subprocess.run(["open","-g","-a",name],check=True,timeout=20)

def scroll_values(bundle):
    text=node_text(inspect(bundle))
    match=re.search(r"Scroll: page=(\d+) left=(\d+) right=(\d+) rightX=(\d+)",text)
    assert match, "No observable scroll state"
    return tuple(map(int,match.groups()))

def area_number(info,title):
    exact=[a for a in info['areas'] if a['title']==title]
    if exact: return exact[0]['label']
    controls=[t for t in info['targets'] if t['title']==title]
    if controls:
        frame=controls[0]['frame']
        matches=[a for a in info['areas'] if a['frame']==frame]
        if matches: return matches[0]['label']
    raise AssertionError(f"No nested area {title}: {info['areas']}")

def record(payload):
    payload['build_sha256']=hashlib.sha256((APP/'Contents/MacOS/KeyRow').read_bytes()).hexdigest()
    payload['time_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    report=ROOT/'outputs/verification.json'
    records=json.loads(report.read_text()) if report.exists() else []
    records.append(payload);report.write_text(json.dumps(records,indent=2)+'\n')
    if (ROOT/'work/overlay-preview.png').exists():
        evidence=ROOT/'outputs/verification-evidence';evidence.mkdir(exist_ok=True)
        slug=re.sub(r'[^a-z0-9]+','-',payload.get('browser',payload.get('app','native')).lower())
        shutil.copy(ROOT/'work/overlay-preview.png',evidence/f'{slug}-overlay.png')
    print(json.dumps(payload),flush=True)

if __name__ == "__main__":
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument("--browser", default="com.google.Chrome");parser.add_argument("--name",default="Google Chrome");parser.add_argument("--scenario",default="fixture")
    args=parser.parse_args()
    if args.scenario == "wheel":
        driver('key','Escape');driver('focus',args.browser)
        area=next(a for a in state()['areas'] if a['title']=='Left scrolling area')
        x,y,w,h=area['frame']; point=(x+w/2,y+h/2)
        for options in [[],['line'],['pid'],['phase'],['pid','phase']]:
            before=scroll_values(args.browser)
            driver('wheel',args.browser,*point,-3 if 'line' in options else -120,*options)
            after=scroll_values(args.browser)
            print(options,before,'->',after,flush=True)
        raise SystemExit(0)
    launch(args.name)
    if args.browser == 'com.google.Chrome':
        driver('key','Escape');driver('focus',args.browser);driver('key','n','cmd')
        driver('window',args.browser,60,60,1400,1050)
    navigate(args.browser,"http://127.0.0.1:8765/browser-fixture.html",new_tab=args.browser!='com.google.Chrome')
    expect(args.browser,"KeyRow browser verification")
    info=hint(args.browser,"Count click")
    assert not any(t["title"] == "Disabled button" for t in info["targets"])
    assert not any(t["title"] == "Bottom button" for t in info["targets"])
    expect(args.browser,"Clicks: 1")
    hint(args.browser,"Count click",gesture="double-hint")
    expect(args.browser,"Double clicks: 1")
    hint(args.browser,"Shadow click")
    expect(args.browser,"Shadow clicked")
    hint(args.browser,"Iframe click")
    expect(args.browser,"Iframe clicked")
    info=activate(args.browser,"scroll")
    before=scroll_values(args.browser)
    left=area_number(info,'Left scrolling area');right=area_number(info,'Right scrolling area')
    driver("key",left)
    driver("key","j","hold","0.4")
    after_left=scroll_values(args.browser)
    assert after_left[1]>before[1] and after_left[0]==before[0] and after_left[2]==before[2],f"Left scroll failed: {before} -> {after_left}"
    driver("key",right)
    driver("key","j","hold","0.4")
    after_right=scroll_values(args.browser)
    assert after_right[2]>after_left[2] and after_right[1]==after_left[1],f"Right scroll failed: {after_left} -> {after_right}"
    driver("key","l","hold","0.3")
    after_horizontal=scroll_values(args.browser)
    assert after_horizontal[3]>after_right[3],f"Horizontal scroll failed: {after_right} -> {after_horizontal}"
    driver("key","0")
    driver("key","j","hold","0.4")
    driver("key","Escape");wait_mode("idle")
    after_page=scroll_values(args.browser)
    assert after_page[0]>before[0],f"Page scroll failed: {before} -> {after_page}"
    expect(args.browser,"Console errors: 0")
    record({"browser": args.name, "scenario":"fixture","status":"PASS", "clicks":True, "double_click":True,"shadow_dom":True,"iframe":True,"scroll":after_page,"console_errors":0,"nested_scroll_areas":len(info["areas"]),"scan_ms":info.get("milliseconds"),"targets":len(info["targets"])})
