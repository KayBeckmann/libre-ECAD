#!/usr/bin/env python3
"""Browser acceptance for M4 after smoke-m4.py; only synthetic test data."""
import json
import os
from pathlib import Path
import re
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
import importlib.util

spec=importlib.util.spec_from_file_location('smoke_m4',Path(__file__).with_name('smoke-m4.py'))
smoke=importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)
state=json.loads(Path('/tmp/libre-ecad-m4-state.json').read_text())
WEB=os.environ.get('LIBRE_ECAD_URL','http://127.0.0.1:8185')
a=state['a']; project=state['projects'][1]; path=smoke.P+'projects/'+project['id']+'/drawing'
errors=[];external=[]
if not os.environ.get('M4_INSPECT'):
    latest=smoke.request(path,token=a['token'])
    initial=smoke.request(path+'/history',token=a['token'])['versions'][0]['drawing']
    smoke.request(path,{'version':latest['version'],'drawing':initial},a['token'],method='PUT')
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True)
    context=browser.new_context(viewport={'width':1600,'height':1000})
    def route(r):
        if urlparse(r.request.url).netloc!=urlparse(WEB).netloc:external.append(r.request.url);r.abort()
        else:r.continue_()
    context.route('**/*',route)
    page=context.new_page();page.set_default_timeout(12000);page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(WEB);page.wait_for_load_state('networkidle')
    page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
    def field(label,value):
        f=page.get_by_role('textbox',name=label,exact=True);f.click();page.wait_for_timeout(200);f.press('ControlOrMeta+A');f.press('Backspace');f.press_sequentially(value,delay=15);page.wait_for_timeout(200)
    field('Benutzername',a['username']);field('Passwort',a['password'])
    page.get_by_role('button',name='Anmelden',exact=True).click()
    page.get_by_role('button',name=re.compile('^Projekte')).click()
    page.get_by_role('button',name=re.compile('^TEST M4 motor')).click()
    page.get_by_role('button',name='Schaltplan öffnen',exact=True).click()
    expect(page.get_by_text('BAUTEILBIBLIOTHEK',exact=True)).to_be_visible()
    page.screenshot(path='/tmp/libre-m4-editor.png')
    Path('/tmp/libre-m4-aria.txt').write_text(page.locator('body').aria_snapshot())
    if os.environ.get('M4_INSPECT'):
        print('Loaded editor; screenshot and accessibility snapshot in /tmp/libre-m4-*')

    else:
        # Select the relay contact by its real canvas semantics, rename its device.
        before=smoke.request(path,token=a['token']);drawing=before['drawing']
        relay=next(o for o in drawing['devices'] if o['type']=='relay')
        page.get_by_role('button',name='Symbol '+relay['bmk'],exact=True).click()
        page.get_by_role('button',name='Kennung / Anschlüsse',exact=True).click()
        field('BMK','TEST-K-M4');page.get_by_role('button',name='Übernehmen',exact=True).click()
        expect(page.get_by_role('button',name='Symbol TEST-K-M4',exact=True)).to_be_visible()
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('V'+str(before['version']+1),exact=True)).to_be_visible()
        after=smoke.request(path,token=a['token'])
        changed=next(o for o in after['drawing']['devices'] if o['id']==relay['id'])
        assert changed['bmk']=='TEST-K-M4'
        assert sum(o['deviceId']==relay['id'] for o in after['drawing']['instances'])==2
        # Jump via derived cross-reference to the other sheet and back.
        page.get_by_role('button',name=re.compile('^Blatt 2')).click()
        expect(page.get_by_role('button',name='Symbol TEST-K-M4',exact=True)).to_be_visible()
        page.screenshot(path='/tmp/libre-m4-second-sheet.png')
        # Move and save with a real pointer drag; ID and BMK are retained.
        symbol=page.get_by_role('button',name='Symbol TEST-K-M4',exact=True)
        box=symbol.bounding_box();x=box['x']+box['width']/2;y=box['y']+box['height']/2
        page.mouse.move(x,y);page.mouse.down();page.mouse.move(x+50,y+30,steps=8);page.mouse.up()
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('V'+str(after['version']+1),exact=True)).to_be_visible()
        moved=smoke.request(path,token=a['token']);old_view=next(o for o in after['drawing']['instances'] if o['deviceId']==relay['id'] and o['symbol']=='coil');new_view=next(o for o in moved['drawing']['instances'] if o['id']==old_view['id'])
        assert (new_view['x'],new_view['y'])!=(old_view['x'],old_view['y'])
        assert next(o for o in moved['drawing']['devices'] if o['id']==relay['id'])['bmk']=='TEST-K-M4'
        # Place two new components on sheet 2 through actual pointer taps.
        box=page.get_by_role('button',name='Symbol TEST-K-M4',exact=True).bounding_box()
        scale=box['width']/96
        origin_x=box['x']+box['width']/2-new_view['x']*scale
        origin_y=box['y']+box['height']/2-new_view['y']*scale
        for label,xp,yp in [('Schutzgerät',300,480),('Klemme',300,620)]:
            page.get_by_role('button',name=label,exact=True).click()
            page.mouse.click(origin_x+xp*scale,origin_y+yp*scale)
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('V'+str(moved['version']+1),exact=True)).to_be_visible()
        placed=smoke.request(path,token=a['token'])
        previous_ids={o['id'] for o in moved['drawing']['instances']}
        new_instances=[o for o in placed['drawing']['instances'] if o['id'] not in previous_ids]
        assert len(new_instances)==2
        breaker=next(o for o in new_instances if o['symbol']=='breaker')
        terminal=next(o for o in new_instances if o['symbol']=='terminal')
        page.get_by_role('checkbox',name='Verbinden',exact=True).click()
        for inst,pin in [(breaker,'2'),(terminal,'1')]:
            page.locator('[flt-semantics-identifier="ecad-hit-port-port-'+inst['id']+'-'+pin+'"]').click()
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('V'+str(placed['version']+1),exact=True)).to_be_visible()
        wired=smoke.request(path,token=a['token'])
        assert len(wired['drawing']['wires'])==len(placed['drawing']['wires'])+1
        bmk1=next(o for o in wired['drawing']['devices'] if o['id']==breaker['deviceId'])['bmk']
        bmk2=next(o for o in wired['drawing']['devices'] if o['id']==terminal['deviceId'])['bmk']
        connection=page.get_by_role('group',name=bmk1+':2 -> '+bmk2+':1',exact=True)
        connection.get_by_role('button',name='Verbindung bearbeiten').click()
        page.wait_for_timeout(350)
        Path('/tmp/libre-m4-wire-menu.txt').write_text(page.locator('body').aria_snapshot())
        page.screenshot(path='/tmp/libre-m4-wire-menu.png')
        page.get_by_role('menuitem',name='Verbindung trennen',exact=True).click()
        page.get_by_role('button',name='Bestätigen',exact=True).click()
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('V'+str(wired['version']+1),exact=True)).to_be_visible()
        moved=smoke.request(path,token=a['token'])
        assert len(moved['drawing']['wires'])==len(placed['drawing']['wires'])
        page.get_by_role('checkbox',name='Auswählen',exact=True).click()
        page.get_by_role('button',name='Symbol TEST-K-M4',exact=True).click()
        # Concurrent server edit provokes an explicit comparison, cancel retains draft.
        page.get_by_role('button',name='Kennung / Anschlüsse',exact=True).click();field('Bezeichnung','TEST local conflict');page.get_by_role('button',name='Übernehmen',exact=True).click()
        remote=json.loads(json.dumps(moved['drawing']));remote['devices'][0]['label']='TEST remote conflict'
        current=smoke.request(path,{'version':moved['version'],'drawing':remote},a['token'],method='PUT')
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('Konflikt: Arbeitsstände vergleichen',exact=True)).to_be_visible()
        page.screenshot(path='/tmp/libre-m4-conflict.png')
        page.get_by_role('button',name='Entwurf behalten / abbrechen',exact=True).click()
        assert smoke.request(path,token=a['token'])['drawing']==remote
        expect(page.get_by_text(re.compile('ungespeichert'))).to_be_visible()
        page.get_by_role('button',name='Speichern',exact=True).click()
        page.get_by_role('button',name='Serverzeichnung übernehmen',exact=True).click()
        expect(page.get_by_text('V'+str(current['version']),exact=True)).to_be_visible()
        # History loads a saved drawing into the editor without silently writing.
        page.get_by_role('button',name='Historie',exact=True).click()
        page.get_by_role('button',name=re.compile('^Arbeitsstand ')).first.click()
        page.get_by_role('button',name='Als Entwurf laden',exact=True).click()
        # Latest content is unchanged; deliberately create a local draft for outage.
        page.get_by_role('button',name='Symbol TEST-K-M4',exact=True).click()
        page.get_by_role('button',name='Kennung / Anschlüsse',exact=True).click();field('Bezeichnung','TEST retained offline draft');page.get_by_role('button',name='Übernehmen',exact=True).click()
        def offline(r):r.abort()
        context.route('**/api/company/**',offline)
        page.get_by_role('button',name=re.compile('^Verbindung prüfen')).click()
        expect(page.get_by_text(re.compile('Backend nicht erreichbar oder Zugriff entzogen'))).to_be_visible()
        expect(page.get_by_role('button',name='Speichern',exact=True)).to_be_disabled()
        expect(page.get_by_role('checkbox',name='Verbinden',exact=True)).to_be_disabled()
        expect(page.get_by_text(re.compile('ungespeichert'))).to_be_visible()
        page.screenshot(path='/tmp/libre-m4-offline.png')
        context.unroute('**/api/company/**',offline)
        page.get_by_role('button',name=re.compile('^Verbindung prüfen')).click()
        expect(page.get_by_role('button',name='Speichern',exact=True)).to_be_enabled()
        expect(page.get_by_text(re.compile('Backend nicht erreichbar oder Zugriff entzogen'))).to_have_count(0)
        page.get_by_role('button',name='Speichern',exact=True).click()
        expect(page.get_by_text('V'+str(current['version']+1),exact=True)).to_be_visible()
        # Narrow layout is view-only; no overflow or editable tool.
        page.set_viewport_size({'width':780,'height':850})
        expect(page.get_by_text('Darstellung zu klein für Bearbeitung',exact=True)).to_be_visible()
        page.screenshot(path='/tmp/libre-m4-small.png')
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        assert not errors,errors
        assert not external,external
        print('PASS browser M4: placement/connect/disconnect, canvas device editing, cross-sheet rename, cross-reference navigation, pointer drag, CAS conflict/cancel/server choice, history, offline draft/reconnection, narrow view, no external resources or JS errors')
    browser.close()
