#!/usr/bin/env python3
"""Additional real-interface checks. Change preferences in the settings UI first."""
import argparse
import verify as v

BUNDLE = 'com.google.Chrome'

def fixture():
    v.navigate(BUNDLE, 'http://127.0.0.1:8765/browser-fixture.html')
    v.expect(BUNDLE, 'Clicks: 0')

def target(info, name):
    return next(t for t in info['targets'] if t['title'] == name)

def manual():
    fixture()
    info = v.activate(BUNDLE)
    label = target(info, 'Count click')['label']
    v.driver('hint', label)
    selected = v.wait_mode('clicking')
    assert selected['prefix'] == label
    v.expect(BUNDLE, 'Clicks: 0')
    v.driver('key', 'Backspace')
    assert v.state()['prefix'] == label[:-1]
    v.driver('key', 'Escape')
    info = v.activate(BUNDLE)
    initial = v.state()['selected']
    v.driver('key', 'Tab'); assert v.state()['selected'] != initial
    v.driver('key', 'Tab', 'shift'); assert v.state()['selected'] == initial
    v.driver('key', 'n', 'ctrl'); assert v.state()['selected'] != initial
    v.driver('key', 'p', 'ctrl'); assert v.state()['selected'] == initial
    v.driver('hint', target(info, 'Count click')['label'])
    v.driver('key', 'Return');v.wait_mode('idle');v.expect(BUNDLE, 'Clicks: 1')
    info = v.activate(BUNDLE)
    v.driver('hint', target(info, 'Count click')['label'])
    v.driver('key', 'Return', 'shift');v.wait_mode('idle');v.expect(BUNDLE, 'Context clicks: 1')
    info = v.activate(BUNDLE)
    v.driver('hint', target(info, 'Open test link')['label'])
    v.driver('key', 'Return', 'cmd');v.wait_mode('idle')
    v.driver('key', 'Tab', 'ctrl');v.expect(BUNDLE, 'new-tab=true');v.driver('key', 'w', 'cmd')
    v.record({'browser':'Google Chrome','scenario':'manual controls','status':'PASS','manual_click':True,'tab_shift_tab':True,'control_n_p':True,'backspace':True,'right_click':True,'command_click_new_tab':True})

def chain():
    fixture()
    info=v.activate(BUNDLE)
    v.driver('hint',target(info,'Count click')['label']);v.wait_mode('clicking');v.expect(BUNDLE,'Clicks: 1')
    info=v.state();v.driver('hint',target(info,'Practice text')['label']);v.wait_mode('idle')
    v.driver('text','KeyRow chain verified');v.expect(BUNDLE,'KeyRow chain verified')
    v.record({'browser':'Google Chrome','scenario':'chain clicks','status':'PASS','relabel_after_click':True,'input_ends_chain':True,'typing':True})

def ignored():
    v.driver('focus',BUNDLE);v.driver('hotkey','click');v.wait_mode('idle')
    v.driver('hotkey','scroll');v.wait_mode('idle')
    v.record({'browser':'Google Chrome','scenario':'ignored app','status':'PASS','click_disabled':True,'scroll_disabled':True})

def typing():
    fixture();v.hint(BUNDLE,'Practice text');v.driver('text',' ')
    fields=[n for n in v.inspect(BUNDLE) if n['role']=='AXTextField' and n.get('AXTitle')=='Practice text']
    assert fields and fields[0].get('AXValue')==' ', 'Immediate space was intercepted after focusing input'
    v.driver('key','Return');v.expect(BUNDLE,'Input returns: 1')
    v.record({'browser':'Google Chrome','scenario':'immediate typing','status':'PASS','space_after_focus':True,'return_passes_to_input':True})

def scrolling():
    fixture();info=v.activate(BUNDLE,'scroll')
    v.driver('key',v.area_number(info,'Left scrolling area'))
    before=v.scroll_values(BUNDLE);v.driver('key','d');after=v.scroll_values(BUNDLE)
    assert after[1]>before[1] and after[0]==before[0] and after[2]==before[2]
    v.driver('key','u');assert v.scroll_values(BUNDLE)[1]<after[1]
    v.driver('key','g','shift');bottom=v.scroll_values(BUNDLE)[1];assert bottom>after[1]
    v.driver('key','g');v.driver('key','g');assert v.scroll_values(BUNDLE)[1]==0
    v.driver('key','j','shift','hold','.2');assert v.scroll_values(BUNDLE)[1]>0
    v.driver('key','Escape');v.wait_mode('idle')
    v.record({'browser':'Google Chrome','scenario':'scroll commands','status':'PASS','half_page_down_up':True,'top_bottom':True,'dash':True})

parser=argparse.ArgumentParser();parser.add_argument('scenario',choices=['manual','chain','ignored','scrolling','typing']);args=parser.parse_args()
try: globals()[args.scenario]()
finally:
    if v.state()['mode']!='idle':v.driver('key','Escape')
