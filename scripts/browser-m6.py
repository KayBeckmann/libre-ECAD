#!/usr/bin/env python3
"""Browser acceptance: scoped credential consent, proposal comparison and no automatic acceptance."""
import importlib.util,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
spec=importlib.util.spec_from_file_location('m4',Path(__file__).with_name('smoke-m4.py'));m4=importlib.util.module_from_spec(spec);spec.loader.exec_module(m4)
state=json.loads(Path('/tmp/libre-ecad-m6-state.json').read_text());a=state['a'];WEB=m4.WEB
project=m4.request(m4.P+'projects/'+state['projectId'],token=a['token']);errors=[]
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True);page=browser.new_page(viewport={'width':1600,'height':1000});page.set_default_timeout(20000)
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(WEB);page.wait_for_load_state('networkidle');page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
    expect(page.get_by_text('Offlineprojekte öffnen',exact=True)).to_have_count(0)
    def field(label,value):
        f=page.get_by_role('textbox',name=label,exact=True);f.click();page.wait_for_timeout(100);f.press('ControlOrMeta+A');f.press('Backspace');f.press_sequentially(value,delay=4)
    field('Benutzername',a['username']);field('Passwort',a['password']);page.get_by_role('button',name='Anmelden',exact=True).click()
    expect(page.get_by_text('Team und Projekte im Blick.',exact=True)).to_be_visible()
    page.get_by_role('button',name=re.compile('^Projekte')).click();page.get_by_role('button',name=re.compile('^'+re.escape(project['name']))).click()
    expect(page.get_by_text('Offline vorbereiten',exact=True)).to_have_count(0)
    page.get_by_role('button',name='API / MCP',exact=True).click()
    expect(page.get_by_text('Zeichnungsvorschläge',exact=True)).to_be_visible()
    page.get_by_role('button',name=re.compile('^TEST browser comparison')).click()
    expect(page.get_by_role('tabpanel',name=re.compile('Aktueller Serverstand Vorgeschlagener Stand'))).to_be_visible()
    page.set_viewport_size({'width':780,'height':850})
    expect(page.get_by_role('button',name='Verglichen · Vorschlag übernehmen',exact=True)).to_be_disabled()
    page.set_viewport_size({'width':1600,'height':1000})
    page.get_by_role('tab',name='Daten vergleichen',exact=True).click()
    expect(page.get_by_role('tab',name='Daten vergleichen',exact=True)).to_have_attribute('aria-selected','true')
    page.get_by_role('tab',name='Pläne vergleichen',exact=True).click()
    page.screenshot(path='/tmp/libre-m6-comparison.png')
    page.get_by_role('button',name='Abbrechen',exact=True).click()
    assert m4.request(m4.P+'projects/'+state['projectId'],token=a['token'])['version']==project['version']
    page.get_by_role('button',name=re.compile('^TEST browser comparison')).click()
    page.get_by_role('button',name='Verglichen · Vorschlag übernehmen',exact=True).click()
    expect(page.get_by_role('button',name='TEST browser comparison Basis V4 · Übernommen',exact=True)).to_be_visible()
    applied=m4.request(m4.P+'projects/'+state['projectId'],token=a['token'])
    assert applied['version']==project['version']+1 and applied['activity']['proposalId']==state['pending']['id']
    page.get_by_role('button',name='Zugang für dieses Projekt erstellen',exact=True).click()
    expect(page.get_by_role('button',name='Zugang erstellen',exact=True)).to_be_disabled()
    field('Bezeichnung, z. B. lokale Assistenz','TEST browser scoped access')
    page.get_by_role('checkbox',name='Datenzugriff auf dieses Projekt bewusst erlauben',exact=True).click()
    with page.expect_response(lambda r:r.url.endswith('/automation/tokens') and r.request.method=='POST') as response:
        page.get_by_role('button',name='Zugang erstellen',exact=True).click()
    credential=response.value.json()
    expect(page.get_by_text('Zugang einmalig kopieren',exact=True)).to_be_visible()
    page.get_by_role('button',name='Schließen',exact=True).click()
    # Cleanup only this temporary credential; never put its cleartext in screenshots/logs.
    m4.request(m4.P+'automation/tokens/'+credential['id']+'/revoke',{},a['token'])
    page.get_by_role('button',name='Refresh',exact=True).click() if page.get_by_role('button',name='Refresh',exact=True).count() else None
    page.set_viewport_size({'width':780,'height':850});page.screenshot(path='/tmp/libre-m6-compact.png')
    assert not errors,errors
    browser.close()
print('PASS browser M6: web has no offline entry, side-by-side review, cancellation, explicit apply, scoped credential consent, compact screen, no JS errors')
