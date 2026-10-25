#!/usr/bin/env python3
"""Real Chromium acceptance after smoke-symbols.py; synthetic test records only."""
import importlib.util, json, os, re
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
spec=importlib.util.spec_from_file_location('m4',Path(__file__).with_name('smoke-m4.py'))
m4=importlib.util.module_from_spec(spec);spec.loader.exec_module(m4)
state=json.loads(Path('/tmp/libre-ecad-symbols-state.json').read_text());a=state['a'];errors=[]
path=m4.P+'projects/'+state['projectId']+'/drawing'
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True)
    page=browser.new_page(viewport={'width':1600,'height':1000});page.set_default_timeout(20000)
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(m4.WEB);page.wait_for_load_state('networkidle')
    page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
    def field(label,value):
        f=page.get_by_role('textbox',name=label,exact=True);f.click();page.wait_for_timeout(100);f.press('ControlOrMeta+A');f.press('Backspace');f.press_sequentially(value,delay=5)
    def inspect(name):
        page.wait_for_timeout(500);Path('/tmp/libre-symbols-'+name+'.txt').write_text(page.locator('body').aria_snapshot());page.screenshot(path='/tmp/libre-symbols-'+name+'.png')
    field('Benutzername',a['username']);field('Passwort',a['password']);page.get_by_role('button',name='Anmelden',exact=True).click()
    expect(page.get_by_text('Team und Projekte im Blick.',exact=True)).to_be_visible()
    page.get_by_role('button',name=re.compile('^Artikel')).first.click()
    page.get_by_role('button',name=re.compile(re.escape(state['articleName']))).click()
    page.get_by_role('button',name='Schaltsymbol bearbeiten',exact=True).click()
    expect(page.get_by_text('Schaltsymbol zeichnen',exact=True)).to_be_visible()
    inspect('designer')
    if os.environ.get('SYMBOL_INSPECT'): raise SystemExit(0)
    field('Symbolname','TEST gezeichneter Schließer')
    page.get_by_text('Linie',exact=True).click()
    # Center of the symbol canvas lies between the fixed 260/230 px side panels.
    page.mouse.move(900,620);page.mouse.down();page.mouse.move(980,620,steps=10);page.mouse.up()
    page.get_by_role('button',name='Symbol übernehmen',exact=True).click()
    inspect('article')
    for _ in range(8):
        if page.get_by_role('button',name='Artikel speichern',exact=True).count(): break
        page.mouse.move(1285,850);page.mouse.wheel(0,700);page.wait_for_timeout(250)
    inspect('article-bottom')
    page.get_by_role('button',name='Artikel speichern',exact=True).click()
    page.wait_for_timeout(800)
    article=m4.request(m4.P+'articles/'+state['articleId'],token=a['token'])
    assert article['layers']['symbol']['definition']['name']=='TEST gezeichneter Schließer'
    assert len(article['layers']['symbol']['definition']['primitives'])==3
    # Navigate back through the actual application routes.
    page.get_by_role('button',name='Back',exact=True).click()
    page.get_by_role('button',name=re.compile('^Projekte')).click()
    page.get_by_role('button',name=re.compile('^'+re.escape(state['projectName']))).click()
    page.get_by_role('button',name='Schaltplan öffnen',exact=True).click()
    expect(page.get_by_text('BAUTEILBIBLIOTHEK',exact=True)).to_be_visible()
    page.wait_for_timeout(500)
    before=m4.request(path,token=a['token']);d=before['drawing']
    supply=next(i for i in d['instances'] if i['symbol']=='supply3')
    bmk=next(v['bmk'] for v in d['devices'] if v['id']==supply['deviceId'])
    box=page.get_by_role('button',name='Symbol '+bmk,exact=True).bounding_box()
    scale=box['width']/96;ox=box['x']+box['width']/2-supply['x']*scale;oy=box['y']+box['height']/2-supply['y']*scale
    page.get_by_role('button',name='Artikelsymbol einfügen',exact=True).click()
    page.get_by_role('button',name=re.compile(re.escape(state['articleName']))).click()
    page.wait_for_timeout(500)
    inspect('placing')
    page.mouse.click(ox+800*scale,oy+520*scale)
    page.wait_for_timeout(300)
    inspect('placed')
    page.get_by_role('button',name='Speichern',exact=True).click()
    expect(page.get_by_text('V'+str(before['version']+1),exact=True)).to_be_visible()
    saved=m4.request(path,token=a['token']);d=saved['drawing']
    custom=next(i for i in d['instances'] if i['symbol'].startswith('custom_'))
    assert len(d['symbols'])==1 and d['symbols'][0]['source']['version']==article['version']
    page.get_by_role('checkbox',name='Auswählen',exact=True).click()
    custom_bmk=next(v['bmk'] for v in d['devices'] if v['id']==custom['deviceId'])
    page.get_by_role('button',name='Symbol '+custom_bmk,exact=True).click()
    page.get_by_role('button',name='Spule zuordnen / ändern',exact=True).click()
    coil=next(i for i in d['instances'] if i['symbol']=='coil')
    coil_bmk=next(v['bmk'] for v in d['devices'] if v['id']==coil['deviceId'])
    page.get_by_role('button',name=re.compile('^'+re.escape(coil_bmk))).click()
    page.get_by_role('button',name='Speichern',exact=True).click()
    expect(page.get_by_text('V'+str(saved['version']+1),exact=True)).to_be_visible()
    married=m4.request(path,token=a['token'])['drawing']
    new=next(i for i in married['instances'] if i['id']==custom['id'])
    assert new['deviceId']==coil['deviceId'] and new['portMap']=={'13':'43','14':'44'}
    assert len(married['wires'])==7
    inspect('drawing')
    page.get_by_role('button',name='Dokumente und Freigabe',exact=True).click()
    with page.expect_download() as download:page.get_by_role('button',name='PDF herunterladen',exact=True).click()
    download.value.save_as('/tmp/libre-symbols-browser.pdf')
    assert Path('/tmp/libre-symbols-browser.pdf').read_bytes().startswith(b'%PDF')
    assert not errors,errors
    print('PASS browser: edit vector symbol, persist article, insert versioned symbol, marry fourth contact across sheets, retain three-phase wiring and export PDF')
    browser.close()
