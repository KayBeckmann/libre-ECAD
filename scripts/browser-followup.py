#!/usr/bin/env python3
"""Real Chromium flows for the six Vault follow-up requirements."""
import importlib.util, json, os, re, time
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
spec = importlib.util.spec_from_file_location('m4', Path(__file__).with_name('smoke-m4.py'))
m4 = importlib.util.module_from_spec(spec); spec.loader.exec_module(m4)
state = json.loads(Path('/tmp/libre-ecad-followup-state.json').read_text())
a, employee, group, project = (state[k] for k in ('a', 'employee', 'group', 'project'))
# Reset only this script's own synthetic drawing when re-running acceptance.
assert a['username'].startswith('followup-') and project['name'].startswith('TEST Nachtrag')
drawing_path = m4.P + 'projects/' + project['id'] + '/drawing'
current = m4.request(drawing_path, token=a['token'])
if current['drawing'] != state['drawing']:
    m4.request(drawing_path, {'version': current['version'], 'drawing': state['drawing']}, a['token'], method='PUT')
errors = []
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1800, 'height': 1100})
    page.set_default_timeout(20000)
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto(m4.WEB); page.wait_for_load_state('networkidle')
    page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
    def field(label, value):
        f = page.get_by_role('textbox', name=label, exact=True)
        f.click(); page.wait_for_timeout(100); f.press('ControlOrMeta+A'); f.press('Backspace'); f.press_sequentially(value, delay=2)
    def button(name):
        # Flutter merges an open tooltip into its parent's accessible name.
        return page.get_by_role('button', name=re.compile(r'^Back(?: Back)?$')) if name == 'Back' else page.get_by_role('button', name=name, exact=True)
    def inspect(name):
        page.wait_for_timeout(350)
        Path('/tmp/libre-followup-' + name + '.txt').write_text(page.locator('body').aria_snapshot())
        page.screenshot(path='/tmp/libre-followup-' + name + '.png')
    def palette(name):
        for _ in range(10):
            if button(name).count(): break
            page.mouse.move(180, 760); page.mouse.wheel(0, -500); page.wait_for_timeout(100)
        button(name).click()
    field('Benutzername', a['username']); field('Passwort', a['password']); button('Anmelden').click()
    expect(page.get_by_text('Team und Projekte im Blick.', exact=True)).to_be_visible()
    page.get_by_role('button', name=re.compile('^Projekte')).click()
    button('Gruppen & Mitarbeiter').click()
    page.get_by_role('button', name=re.compile('^' + re.escape(group['name']))).click()
    page.get_by_role('checkbox', name=employee['username'], exact=True).click()
    button('Gruppe speichern').click()
    expect(button('Gruppe anlegen')).to_be_visible()
    page.wait_for_timeout(500)
    m4.request(m4.P + 'projects/' + project['id'], token=employee['token'], expected=404)
    inspect('group-revoked')
    # Reverse view: choose employee and assign the group directly.
    page.get_by_role('button', name=re.compile('Gruppen für Mitarbeiter freischalten')).click()
    page.get_by_role('menuitem', name=employee['username'], exact=True).click()
    page.get_by_role('checkbox', name=group['name'], exact=True).click()
    page.wait_for_timeout(500)
    m4.request(m4.P + 'projects/' + project['id'], token=employee['token'])
    inspect('employee-groups')
    button('Back').click()
    page.get_by_role('button', name=re.compile('^Projektgruppe')).click()
    page.get_by_role('menuitem', name=group['name'], exact=True).click()
    page.get_by_role('button', name=re.compile('^' + re.escape(project['name']))).click()
    button('Schaltplan öffnen').click()
    expect(page.get_by_text('BAUTEILBIBLIOTHEK', exact=True)).to_be_visible()
    inspect('editor')
    if os.environ.get('FOLLOWUP_INSPECT'): raise SystemExit(0)
    # Compute drawing-to-screen coordinates from two semantic symbol hit areas.
    d = state['drawing']; coil, contact = d['instances'][:2]
    def hit(i): return page.locator('[flt-semantics-identifier="ecad-hit-symbol-' + i['id'] + '"]')
    left, right = hit(coil).bounding_box(), hit(contact).bounding_box()
    scale = (right['x'] - left['x']) / (contact['x'] - coil['x'])
    origin_x = left['x'] + left['width']/2 - coil['x']*scale
    origin_y = left['y'] + left['height']/2 - coil['y']*scale
    page.get_by_role('checkbox', name='Rahmenauswahl', exact=True).click()
    page.mouse.move(origin_x + 100*scale, origin_y + 110*scale)
    page.mouse.down(); page.mouse.move(origin_x + 760*scale, origin_y + 430*scale, steps=25); page.mouse.up()
    inspect('selected-frame')
    palette('Makrobibliothek')
    button('Auswahl als Makro speichern (3 Bauteile)').click()
    macro_name = 'TEST Rahmen ' + str(time.time_ns())
    field('Name', macro_name); field('Herkunft', 'Eigene synthetische Auswahl'); field('Lizenz', 'CC0-1.0'); field('Gruppen (Komma getrennt)', 'TEST,Relais')
    button('Makro speichern').click(); page.wait_for_timeout(500)
    macro = next(v for v in m4.request(m4.P + 'macros/?scope=personal', token=a['token'])['macros'] if v['name'] == macro_name)
    assert len(macro['drawing']['instances']) == 3
    assert len(macro['drawing']['devices']) == 1
    assert len(macro['drawing']['wires']) == 2
    assert not macro['drawing'].get('plans')
    field('Name oder Gruppe suchen', macro_name)
    button('Einfügen').click()
    inspect('macro-preview')
    button('Als neue Blätter einfügen').click()
    inspect('after-insert')
    button('Speichern').click(); page.wait_for_timeout(500)
    saved = m4.request(m4.P + 'projects/' + project['id'] + '/drawing', token=a['token'])
    assert len(saved['drawing']['instances']) == 7
    assert len(saved['drawing']['devices']) == 3
    # Existing explicit paired page continuation, verified through the actual UI.
    button('Blattfortsetzung').click()
    field('Signalname', 'TEST-L1'); button('Fortsetzung anlegen').click()
    inspect('after-continuation')
    button('Speichern').click(); page.wait_for_timeout(500)
    saved = m4.request(m4.P + 'projects/' + project['id'] + '/drawing', token=a['token'])
    ends = [c for c in saved['drawing']['continuations'] if c['label'] == 'TEST-L1']
    assert len(ends) == 2 and ends[0]['linkId'] == ends[1]['linkId'] and ends[0]['sheetId'] != ends[1]['sheetId']
    # Contact inspector links to only the coil, not to its peer contact.
    page.get_by_role('checkbox', name='Auswählen', exact=True).click(); hit(contact).click()
    inspect('contact-reference')
    expect(page.get_by_role('button', name=re.compile('Blatt .*Relaisspule'))).to_have_count(1)
    assert not page.get_by_role('button', name=re.compile('Blatt .*Öffner')).count()
    assert not page.get_by_role('button', name=re.compile('Blatt .*Schließer')).count()
    # Return to unified article library.
    button('Back').click(); expect(button('Schaltplan öffnen')).to_be_visible()
    inspect('return-project')
    page.wait_for_timeout(350); button('Back').click()
    expect(button('Gruppen & Mitarbeiter')).to_be_visible()
    page.wait_for_timeout(350); button('Back').click()
    expect(page.get_by_text('Team und Projekte im Blick.', exact=True)).to_be_visible()
    page.get_by_role('button', name=re.compile('^Artikelbibliothek')).click()
    inspect('libraries-personal-start')
    expect(page.get_by_role('button', name=re.compile('^TEST-PERSONAL · TEST Bibliothek personal'))).to_be_visible()
    page.get_by_role('checkbox', name='Nur mit Schaltsymbol', exact=True).click()
    expect(page.get_by_role('button', name=re.compile('^TEST-PERSONAL · TEST Bibliothek personal'))).to_be_visible()
    button('Firma').click()
    expect(page.get_by_role('button', name=re.compile('^TEST-COMPANY · TEST Bibliothek company'))).to_be_visible()
    button('Global').click()
    expect(page.get_by_role('group', name=re.compile('^Globaler Artikelkatalog '))).to_be_visible()
    inspect('libraries-global')
    button('Persönlich').click()
    expect(page.get_by_role('button', name=re.compile('^TEST-PERSONAL · TEST Bibliothek personal'))).to_be_visible()
    inspect('libraries-personal')
    assert not errors, errors
    browser.close()
print('PASS browser: groups in both directions, project grouping, framed macro save/insert, paired page references, coil-only contact reference, all three libraries')
