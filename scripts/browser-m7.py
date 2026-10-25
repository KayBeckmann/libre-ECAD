#!/usr/bin/env python3
"""Chromium M7 acceptance against the synthetic smoke-m7 project."""
import base64, importlib.util, json, math, os, re
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
spec=importlib.util.spec_from_file_location('m4',Path(__file__).with_name('smoke-m4.py'))
m4=importlib.util.module_from_spec(spec);spec.loader.exec_module(m4)
state=json.loads(Path('/tmp/libre-ecad-m7-state.json').read_text());a=state['a'];errors=[]
path=m4.P+'projects/'+state['projectId']+'/drawing'
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True)
    page=browser.new_page(viewport={'width':1600,'height':1000});page.set_default_timeout(20000)
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(m4.WEB);page.wait_for_load_state('networkidle')
    page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
    def field(label,value):
        f=page.get_by_role('textbox',name=label,exact=True);f.click();page.wait_for_timeout(80);f.press('ControlOrMeta+A');f.press('Backspace');f.press_sequentially(value,delay=3)
    def button(name):return page.get_by_role('button',name=name,exact=True)
    def inspect(name):
        page.wait_for_timeout(500);Path('/tmp/libre-m7-'+name+'.txt').write_text(page.locator('body').aria_snapshot());page.screenshot(path='/tmp/libre-m7-'+name+'.png')
    def palette(name):
        for _ in range(8):
            if button(name).count():break
            page.mouse.move(180,720);page.mouse.wheel(0,-600);page.wait_for_timeout(150)
        button(name).click()
    field('Benutzername',a['username']);field('Passwort',a['password']);button('Anmelden').click()
    expect(page.get_by_text('Team und Projekte im Blick.',exact=True)).to_be_visible()
    page.get_by_role('button',name=re.compile('^Projekte')).click()
    page.get_by_role('button',name=re.compile('^'+re.escape(state['projectName']))).click()
    button('Schaltplan öffnen').click()
    expect(page.get_by_text('BAUTEILBIBLIOTHEK',exact=True)).to_be_visible()
    inspect('editor')
    palette('Planart / Maßstab')
    inspect('planning')
    if os.environ.get('M7_INSPECT'):raise SystemExit(0)
    expect(page.get_by_text(re.compile('10.*TEST Referenz 10 m'))).to_be_visible()
    button('Planung übernehmen').click()
    palette('Berechnungen')
    inspect('calculations')
    expect(page.get_by_role('group',name='TEST Spannungsfall',exact=True)).to_be_visible()
    page.mouse.move(1100,350);page.mouse.wheel(0,-1200);page.wait_for_timeout(400)
    assert '1.343' in page.locator('body').aria_snapshot()
    inspect('calculations')
    button('Back').click()
    palette('Material / ERP')
    with page.expect_download() as download:
        button('Importvorschau als JSON speichern').click()
    download.value.save_as('/tmp/libre-m7-browser-material.json')
    material=json.loads(Path('/tmp/libre-m7-browser-material.json').read_text());assert len(material['items'])==3
    assert sum(r['quantity'] for r in material['items'])==3
    inspect('material')
    button('Back').click()
    palette('Planart / Maßstab')
    button('Planart Installationsplan').click()
    inspect('plan-menu')
    page.get_by_role('menuitem',name='Aufbauzeichnung',exact=True).click()
    inspect('layout')
    # This alternate view is a local draft until explicitly adopted.
    button('Back').click()
    palette('Planart / Maßstab')
    before=m4.request(path,token=a['token'])
    Path('/tmp/libre-m7-upload.png').write_bytes(base64.b64decode(before['drawing']['plans'][0]['background']['png']))
    with page.expect_file_chooser() as chooser:
        button('Bildvorlage laden').click()
    chooser.value.set_files('/tmp/libre-m7-upload.png')
    field('Quelle / Nutzungsrecht','TEST Chromium eigener Grundriss')
    field('Revision','Browser-1');button('Übernehmen').click()
    button('Maßstab: zwei Punkte wählen').click()
    button('Anschluss 1-X2:1').click();button('Anschluss 1-S5:1').click()
    field('Reale Länge [m]',str(math.hypot(400,40)/40))
    field('Quelle / Bezug','TEST Chromium Referenz')
    field('Perspektive geprüft (ja/nein)','ja');button('Übernehmen').click()
    inspect('uploaded-calibrated')
    button('Planung übernehmen').click();button('Speichern').click()
    expect(page.get_by_text('V'+str(before['version']+1),exact=True)).to_be_visible()
    saved=m4.request(path,token=a['token'])['drawing']
    assert saved['plans'][0]['background']['revision']=='Browser-1'
    assert saved['plans'][0]['calibration']['source']=='TEST Chromium Referenz'
    assert saved['plans'][0]['calibration']['perspectiveConfirmed']
    palette('Makrobibliothek')
    field('Name oder Gruppe suchen',state['macroName'])
    inspect('macro-list')
    page.get_by_label(re.compile('^'+re.escape(state['macroName'])+' ·')).get_by_role('button',name='Einfügen',exact=True).click()
    inspect('macro-preview')
    button('Als neue Blätter einfügen').click()
    button('Speichern').click()
    page.wait_for_timeout(600)
    d=m4.request(path,token=a['token'])['drawing'];assert len(d['devices'])==6 and len(d['plans'])==2
    assert len({r['id'] for plan in d['plans'] for r in plan['routes']})==2
    palette('Planart / Maßstab')
    page.set_viewport_size({'width':800,'height':900});page.wait_for_timeout(300)
    expect(button('Planung übernehmen')).to_be_disabled()
    inspect('compact')
    assert not errors,errors
    browser.close()
    print('PASS M7 browser: image upload/calibration, layout, calculation results, JSON download, macro copies persisted, compact read-only, no JS errors')
