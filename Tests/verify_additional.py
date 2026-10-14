#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path
import verify as v

def pick(info,predicate):
    matches=[target for target in info['targets'] if predicate(target)]
    assert matches, 'Expected control is missing from visible labels'
    return matches[0]

def press_hint(bundle,predicate):
    import time
    deadline=time.monotonic()+15
    while True:
        info=v.activate(bundle)
        matches=[target for target in info['targets'] if predicate(target)]
        if matches: target=matches[0];break
        v.driver('key','Escape')
        assert time.monotonic()<deadline, 'Expected control is missing from visible labels'
        time.sleep(.2)
    v.driver('hint',target['label']);v.wait_mode('idle')
    return info

def native():
    bundle='com.apple.calculator'
    v.launch('Calculator');v.driver('focus',bundle);v.driver('key','Escape')
    info=v.activate(bundle)
    print('Calculator controls:',[(t['title'],t['role']) for t in info['targets'] if t['role']=='AXButton'],flush=True)
    v.driver('key','Escape')
    v.driver('key','Escape')
    press_hint(bundle,lambda t: t['title'].lower() in ['7','seven'])
    nodes=v.expect(bundle,'7')
    assert any(n['role'] in ['AXStaticText','AXTextField','AXTextArea'] and str(n.get('AXValue',n.get('AXTitle',''))) in ['7','7.'] for n in nodes), 'Calculator display did not become 7'
    v.record({'app':'Calculator','scenario':'native','status':'PASS','result':'Digit 7 clicked through a keyboard label'})
    native_finder()
    native_settings()

def native_finder():
    folder=v.ROOT/'work/finder-fixture';folder.mkdir(exist_ok=True)
    filename='KeyRow navigation check.txt';(folder/filename).write_text('KeyRow verification fixture.\n')
    subprocess.run(['open','-g','-a','Finder',str(folder)],check=True)
    v.driver('focus','com.apple.finder')
    press_hint('com.apple.finder',lambda t:t['role']=='AXRadioButton' and t['title']=='list view')
    v.driver('key','a','cmd','alt')
    nodes=v.expect('com.apple.finder',filename)
    textnode=min((n for n in nodes if filename in str(n.get('AXValue',''))+str(n.get('AXTitle',''))+str(n.get('AXDescription','')) and 'frame' in n),key=lambda n:n['frame'][2]*n['frame'][3])
    x,y,w,h=textnode['frame'];point=(x+w/2,y+h/2)
    info=v.activate('com.apple.finder')
    candidates=[t for t in info['targets'] if t['role'] in ['AXRow','AXCell'] and t['frame'][0]<=point[0]<=t['frame'][0]+t['frame'][2] and t['frame'][1]<=point[1]<=t['frame'][1]+t['frame'][3]]
    assert candidates, 'Finder file row was not labelled'
    target=min(candidates,key=lambda t:t['frame'][2]*t['frame'][3])
    v.driver('hint',target['label']);v.wait_mode('idle')
    nodes=v.inspect('com.apple.finder')
    assert any(n['role']=='AXRow' and n.get('AXSelected') is True and n.get('frame',[0,0,0,0])[0]<=point[0]<=n.get('frame',[0,0,0,0])[0]+n.get('frame',[0,0,0,0])[2] and n.get('frame',[0,0,0,0])[1]<=point[1]<=n.get('frame',[0,0,0,0])[1]+n.get('frame',[0,0,0,0])[3] for n in nodes), 'Finder fixture file was not selected'
    v.record({'app':'Finder','scenario':'native','status':'PASS','result':'Fixture file selected in list view through its label'})

def native_settings():
    bundle='com.apple.systempreferences';v.launch('System Settings')
    press_hint(bundle,lambda t: t['title']=='Appearance')
    v.expect(bundle,'Light');v.expect(bundle,'Dark')
    assert any(n['role']=='AXWindow' and n.get('AXTitle')=='Appearance' for n in v.inspect(bundle)), 'Appearance page did not open'
    v.record({'app':'System Settings','scenario':'native','status':'PASS','result':'Appearance page opened through its navigation-row label; no setting changed'})

def live(bundle,name,only=None):
    sites=[('Wikipedia','https://www.wikipedia.org/',lambda t: t['role']=='AXLink' and t['title'].startswith('English'),'en.wikipedia.org'),
           ('GitHub','https://github.com/nchudleigh/homerow',lambda t: t['role']=='AXLink' and t['title'].startswith('README.md'),'/blob/main/README.md'),
           ('Apple','https://www.apple.com/',lambda t: t['role']=='AXLink' and t['title']=='Support','support.apple.com')]
    if only: sites=[site for site in sites if site[0]==only]
    for index,(site,url,predicate,expected) in enumerate(sites):
        v.navigate(bundle,url,new_tab=index==0)
        # Browser tab titles can already contain these words before the new page
        # loads. Wait for the actual document URL and a stable control rectangle.
        import time
        deadline=time.monotonic()+25; previous=None; stable_since=0
        while True:
            nodes=v.inspect(bundle)
            document_ready=any(n['role']=='AXWebArea' and n.get('AXURL','').rstrip('/')==url.rstrip('/') for n in nodes)
            matches=[n for n in nodes if predicate({'role':n['role'],'title':n.get('AXTitle') or n.get('AXDescription') or ''}) and 'frame' in n]
            key=tuple(matches[0]['frame']) if matches and document_ready else None
            if key is not None and key==previous:
                if time.monotonic()-stable_since>=.6:break
            else: previous=key;stable_since=time.monotonic()
            assert time.monotonic()<deadline, 'Document/control did not become ready'
            time.sleep(.1)
        info=press_hint(bundle,predicate)
        deadline=time.monotonic()+15
        while True:
            nodes=v.inspect(bundle)
            if any(n['role']=='AXWebArea' and expected in n.get('AXURL','') for n in nodes): break
            assert time.monotonic()<deadline,'Browser did not navigate to the expected page'
            time.sleep(.1)
        urls=[n['AXURL'] for n in nodes if n['role']=='AXWebArea' and 'AXURL' in n]
        assert any(expected in url for url in urls), f'Link did not navigate: {urls}'
        v.record({'browser':name,'scenario':'live-site','site':site,'status':'PASS','result_url':next(url for url in urls if expected in url),'scan_ms':info.get('milliseconds'),'targets':len(info['targets'])})
    v.driver('key','w','cmd')

def gestures(bundle,name):
    v.navigate(bundle,'http://127.0.0.1:8765/browser-fixture.html')
    v.expect(bundle,'Clicks: 0')
    info=v.activate(bundle)
    target=pick(info,lambda t:t['title']=='Count click')
    v.driver('hint',target['label']);v.wait_mode('clicking')
    v.driver('key','Return','shift');v.wait_mode('idle')
    v.expect(bundle,'Context clicks: 1')
    info=v.activate(bundle)
    target=pick(info,lambda t:t['title']=='Open test link')
    v.driver('hint',target['label']);v.wait_mode('clicking')
    v.driver('key','Return','cmd');v.wait_mode('idle')
    v.driver('key','Tab','ctrl')
    v.expect(bundle,'new-tab=true')
    v.driver('key','w','cmd')
    v.record({'browser':name,'scenario':'gestures','status':'PASS','right_click':True,'command_click_new_tab':True})

def practice():
    bundle='local.keyrow.app'
    v.driver('focus',bundle)
    v.expect(bundle,'Keyboard practice')
    import re
    initial=v.inspect(bundle)
    clicks=int(re.search(r'Clicks: (\d+)',v.node_text(initial)).group(1))
    checkbox=next(n['AXValue'] for n in initial if n['role']=='AXCheckBox')
    v.hint(bundle,'Count click');v.expect(bundle,f'Clicks: {clicks+1}')
    v.hint(bundle,'Enable option')
    assert any(n['role']=='AXCheckBox' and n.get('AXValue')!=checkbox for n in v.inspect(bundle)), 'Checkbox did not toggle'
    v.hint(bundle,'Practice text');v.driver('key','a','cmd');v.driver('text','KeyRow verified')
    assert any(n['role']=='AXTextField' and n.get('AXValue')=='KeyRow verified' for n in v.inspect(bundle)), 'Native input did not receive text'
    info=v.activate(bundle,'scroll');assert len(info['areas'])==2
    before=[n for n in v.inspect(bundle) if n.get('AXDescription')=='Left item 0']
    v.driver('key','j','hold','0.4')
    after=[n for n in v.inspect(bundle) if n.get('AXDescription')=='Left item 0']
    assert before[0]['frame'][1]!=after[0]['frame'][1], 'Native scroll position did not change'
    v.driver('key','Escape')
    v.record({'app':'Native practice window','scenario':'native','status':'PASS','click':True,'checkbox':True,'input_focus':True,'scroll':True})

def probe(name,bundle):
    v.launch(name);v.driver('focus',bundle)
    info=v.activate(bundle)
    print([(t['title'],t['role']) for t in info['targets']],flush=True)
    v.driver('key','Escape')

def mission():
    import time
    subprocess.run(['open','-a','Mission Control'],check=True)
    info=v.wait_mode('clicking')
    target=pick(info,lambda t:t['title']=='KeyRow Practice')
    v.driver('hint',target['label']);v.wait_mode('idle')
    deadline=time.monotonic()+8
    while True:
        dock=v.inspect('com.apple.dock')
        closed=not any(n.get('AXIdentifier') in ['mc','appexpose'] for n in dock)
        front=v.state()['frontApp']
        if closed and front=='KeyRow':break
        assert time.monotonic()<deadline, f'Mission Control selection did not finish: closed={closed}, front={front}'
        time.sleep(.1)
    nodes=v.inspect('local.keyrow.app')
    assert any(n['role']=='AXWindow' and n.get('AXTitle')=='KeyRow Practice' for n in nodes)
    v.record({'scenario':'Mission Control','status':'PASS','auto_activation':True,'window_selection':True,'closed_after_selection':True,'foreground_app':'KeyRow','targets':len(info['targets'])})

parser=argparse.ArgumentParser();parser.add_argument('--scenario',required=True);parser.add_argument('--browser',default='com.google.Chrome');parser.add_argument('--name',default='Google Chrome');parser.add_argument('--site',choices=['Apple','GitHub','Wikipedia'])
args=parser.parse_args()
try:
    if args.scenario=='native': native()
    elif args.scenario=='finder': native_finder()
    elif args.scenario=='settings': native_settings()
    elif args.scenario=='live': live(args.browser,args.name,args.site)
    elif args.scenario=='gestures': gestures(args.browser,args.name)
    elif args.scenario=='practice': practice()
    elif args.scenario=='probe': probe(args.name,args.browser)
    elif args.scenario=='mission': mission()
finally:
    if v.STATE.exists() and v.state()['mode']!='idle': v.driver('key','Escape')
