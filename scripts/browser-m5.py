#!/usr/bin/env python3
"""Real Chromium acceptance of mockup styling and M5 document workflow."""
import json, re, os, hashlib, base64, importlib.util
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
spec=importlib.util.spec_from_file_location('m4',Path(__file__).with_name('smoke-m4.py'));m4=importlib.util.module_from_spec(spec);spec.loader.exec_module(m4)
state=json.loads(Path('/tmp/libre-ecad-m5-state.json').read_text());a=state['a'];WEB=m4.WEB
project=m4.request(m4.P+'projects/'+state['projectId'],token=a['token'])
errors=[];external=[]
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True);context=browser.new_context(viewport={'width':1600,'height':1000});page=context.new_page();page.set_default_timeout(20000)
    page.on('pageerror',lambda e:errors.append(str(e)))
    def route(r):
        if urlparse(r.request.url).netloc!=urlparse(WEB).netloc:external.append(r.request.url);r.abort()
        else:r.continue_()
    context.route('**/*',route)
    page.goto(WEB);page.wait_for_load_state('networkidle');page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
    page.screenshot(path='/tmp/libre-m5-login.png')
    def field(label,value):
        f=page.get_by_role('textbox',name=label,exact=True);f.click();page.wait_for_timeout(100);f.press('ControlOrMeta+A');f.press('Backspace');f.press_sequentially(value,delay=4)
    field('Benutzername',a['username']);field('Passwort',a['password']);page.get_by_role('button',name='Anmelden',exact=True).click()
    expect(page.get_by_text('Team und Projekte im Blick.',exact=True)).to_be_visible();page.screenshot(path='/tmp/libre-m5-home.png')
    page.get_by_role('button',name=re.compile('^Projekte')).click();page.get_by_role('button',name=re.compile('^'+re.escape(project['name']))).click()
    page.get_by_role('button',name='Schaltplan öffnen',exact=True).click();expect(page.get_by_text('BAUTEILBIBLIOTHEK',exact=True)).to_be_visible()
    page.get_by_role('button',name='Dokumente und Freigabe',exact=True).click()
    expect(page.get_by_role('button',name='PDF herunterladen',exact=True)).to_be_visible()
    Path('/tmp/libre-m5-docs-aria.txt').write_text(page.locator('body').aria_snapshot());page.screenshot(path='/tmp/libre-m5-documents.png')
    if os.environ.get('M5_SOURCE_INSPECT'):
        page.get_by_role('button',name=re.compile('^Ausgabequelle ausdrücklich wählen')).click()
        Path('/tmp/libre-m5-source-aria.txt').write_text(page.locator('body').aria_snapshot())
        page.screenshot(path='/tmp/libre-m5-source.png');browser.close();raise SystemExit(0)
    if os.environ.get('M5_INSPECT'):
        print('M5 source selection loaded; screenshots and accessibility tree in /tmp/libre-m5-*')
    else:
        with page.expect_download() as download:page.get_by_role('button',name='PDF herunterladen',exact=True).click()
        download.value.save_as('/tmp/libre-m5-browser-working.pdf');assert Path('/tmp/libre-m5-browser-working.pdf').read_bytes().startswith(b'%PDF')
        # Follow a finding back to its real drawing object, then return.
        page.get_by_role('button',name=re.compile('ist offen. Absicht prüfen.')).first.click()
        expect(page.get_by_text('EIGENSCHAFTEN',exact=True)).to_be_visible()
        page.get_by_role('button',name='Dokumente und Freigabe',exact=True).click()
        page.get_by_role('button',name='Stand fachlich festschreiben',exact=True).click()
        field('Freigabebegründung','TEST: browser acceptance of explicit approval')
        inputs=page.get_by_role('textbox',name=re.compile('^Ausnahme begründen:'))
        for index in range(inputs.count()):
            f=inputs.nth(index);f.click();page.wait_for_timeout(150);f.press('ControlOrMeta+A');f.press('Backspace');f.press_sequentially('TEST: intentional open connection in synthetic example',delay=6);page.wait_for_timeout(150)
        page.get_by_role('checkbox',name='Ich habe diesen Stand und alle Hinweise fachlich geprüft.',exact=True).click()
        page.get_by_role('button',name='Verbindlich festschreiben',exact=True).click()
        expect(page.get_by_role('checkbox',name=re.compile('^Festgeschrieben · Projektversion'))).to_be_visible(timeout=20000)
        with page.expect_download() as download:page.get_by_role('button',name='PDF herunterladen',exact=True).click()
        download.value.save_as('/tmp/libre-m5-browser-approved.pdf')
        latest=m4.request(m4.P+'projects/'+state['projectId']+'/releases',token=a['token'])['releases'][-1]
        assert hashlib.sha256(Path('/tmp/libre-m5-browser-approved.pdf').read_bytes()).hexdigest()==latest['sha256']
        page.screenshot(path='/tmp/libre-m5-release.png')
        page.get_by_role('button',name=re.compile('^Ausgabequelle ausdrücklich wählen')).click()
        page.get_by_role('menuitem',name='Festgeschrieben V'+str(state['release']['version'])+' · '+state['release']['username']+' · '+state['release']['at'],exact=True).click()
        expect(page.get_by_role('checkbox',name='Festgeschrieben · Projektversion '+str(state['release']['version']),exact=True)).to_be_visible()
        with page.expect_download() as download:page.get_by_role('button',name='PDF herunterladen',exact=True).click()
        download.value.save_as('/tmp/libre-m5-browser-old.pdf')
        assert hashlib.sha256(Path('/tmp/libre-m5-browser-old.pdf').read_bytes()).hexdigest()==state['release']['sha256']
        page.set_viewport_size({'width':780,'height':850});expect(page.get_by_role('button',name='PDF herunterladen',exact=True)).to_be_visible();page.screenshot(path='/tmp/libre-m5-compact.png')
        assert not errors,errors;assert not external,external
        print('PASS browser M5: mockup login/home/editor, explicit working PDF, reasoned approval, exact approved PDF download, compact document view, no JS errors or external requests')
    browser.close()
