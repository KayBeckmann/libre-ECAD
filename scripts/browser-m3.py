#!/usr/bin/env python3
"""Live browser acceptance after smoke-m3.py; synthetic fixtures only."""
import json,re,urllib.request,time,os
from urllib.parse import urlparse
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
WEB=os.environ.get('LIBRE_ECAD_URL','http://127.0.0.1:8185')
OP_WEB=os.environ.get('LIBRE_ECAD_OPERATOR_URL','http://127.0.0.1:8186')
state=json.loads(Path('/tmp/libre-ecad-m3-state.json').read_text())
root=Path(__file__).resolve().parents[1]
config=dict(line.split('=',1) for line in (root/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
access={'superadminUsername':config['SUPER_ADMIN_BOOTSTRAP_USERNAME'],'superadminPassword':config['SUPER_ADMIN_BOOTSTRAP_PASSWORD']}
a,b=state['companies']; run=state['run']
errors=[];external=[]
ui_suffix=str(int(time.time()))
ui_name='TEST – Browserbeitrag '+ui_suffix
def api(body):
 r=urllib.request.urlopen(urllib.request.Request(OP_WEB+'/api/operator',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+state['operatorToken']}));return json.load(r)
def company(path,token):
 try:return urllib.request.urlopen(urllib.request.Request(WEB+'/api/company'+path,headers={'Authorization':'Bearer '+token})).status
 except urllib.error.HTTPError as e:return e.code
grant=next(g for g in api({'action':'catalog','operation':'list'})['manufacturers'] if g['id']==b['id'])
if not grant['active']:
 api({'action':'catalog','operation':'manufacturer','companyId':b['id'],'name':grant['name'],'evidence':grant['evidence'],'active':True,'version':grant['version'],'confirmed':True,'reason':'TEST: Browser-Ausgangszustand'})
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True)
 ctx=browser.new_context(viewport={'width':1440,'height':1100})
 def route(r):
  if urlparse(r.request.url).netloc not in {urlparse(WEB).netloc,urlparse(OP_WEB).netloc}:
   external.append(r.request.url);r.abort()
  else:r.continue_()
 ctx.route('**/*',route)
 page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(OP_WEB);page.get_by_label('Benutzername',exact=True).fill(access['superadminUsername']);page.get_by_label('Passwort',exact=True).fill(access['superadminPassword']);page.get_by_role('button',name='Als Superadmin anmelden').click()
 expect(page.get_by_role('heading',name='Firmen & Zugänge')).to_be_visible()
 page.get_by_role('button',name=re.compile('M3 Abnahme A – '+run)).click()
 expect(page.get_by_role('heading',name='Vertrag & Zahlungen')).to_be_visible()
 expect(page.get_by_text('TEST-BELEG-'+run,exact=False).first).to_be_visible()
 page.screenshot(path='/tmp/libre-m3-operator-companies.png',full_page=True)
 page.get_by_role('button',name='Backend sperren',exact=True).click()
 dlg=page.get_by_role('dialog');dlg.get_by_label('Begründung / dokumentierter Vorgang').fill('TEST: Browsersperre; Testnutzer informiert')
 dlg.get_by_role('checkbox').check();dlg.get_by_role('button',name='Bestätigen',exact=True).click()
 expect(page.get_by_role('button',name='Backend entsperren',exact=True)).to_be_visible()
 assert company('/me',a['token'])==401
 page.get_by_role('button',name='Backend entsperren',exact=True).click();dlg.get_by_label('Begründung / dokumentierter Vorgang').fill('TEST: Browserentsperrung');dlg.get_by_role('checkbox').check();dlg.get_by_role('button',name='Bestätigen',exact=True).click();expect(page.get_by_role('button',name='Backend sperren',exact=True)).to_be_visible()
 assert company('/me',a['token'])==401
 page.get_by_role('button',name='Zugriffsprotokoll',exact=True).click();expect(dlg.get_by_text('TEST: Browserentsperrung',exact=True).last).to_be_visible();dlg.get_by_role('button',name='Schließen').click()
 page.get_by_role('button',name=re.compile('M3 Abnahme B – '+run)).click();expect(page.get_by_role('heading',name='Zugänge',exact=True)).to_be_visible()
 page.get_by_role('button',name='Zuordnung ansehen / ändern').click();dlg.get_by_role('button',name='Zuordnung entziehen').click();dlg.get_by_label('Begründung / dokumentierter Vorgang').fill('TEST: Herstellerzuordnung im Browser widerrufen');dlg.get_by_role('checkbox').check();dlg.get_by_role('button',name='Bestätigen',exact=True).click()
 expect(page.locator('#workspace')).to_have_attribute('aria-busy','false');expect(page.get_by_role('button',name='Zuordnung ansehen / ändern')).to_be_visible();page.get_by_role('button',name='Zuordnung ansehen / ändern').click();expect(dlg.get_by_text('nicht aktiv',exact=True)).to_be_visible();dlg.get_by_role('button',name='Geprüfte Identität zuordnen').click();dlg.get_by_label('Begründung / dokumentierter Vorgang').fill('TEST: synthetische Identität erneut zugeordnet');dlg.get_by_role('checkbox').check();dlg.get_by_role('button',name='Bestätigen',exact=True).click();expect(page.get_by_role('button',name='Zuordnung ansehen / ändern')).to_be_visible()
 # Recovery token issued in operator UI, then redeemed in the Flutter UI.
 page.get_by_role('button',name='Aktivierung neu',exact=True).click();dlg.get_by_label('Begründung / dokumentierter Vorgang').fill('TEST: Aktivierungsoberfläche');dlg.get_by_role('checkbox').check();dlg.get_by_role('button',name='Bestätigen',exact=True).click();expect(dlg.get_by_role('heading',name='Aktivierung bereit')).to_be_visible();activation=dlg.locator('.secret').inner_text();dlg.get_by_role('button',name='Schließen').click()
 app=ctx.new_page();app.on('pageerror',lambda e:errors.append(str(e)));app.goto(WEB);app.wait_for_load_state('networkidle');app.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()');app.get_by_role('button',name='Zugang aktivieren',exact=True).click()
 def typefield(label,value):
  f=app.get_by_role('textbox',name=label,exact=True);app.wait_for_timeout(400);f.click();app.wait_for_timeout(250);f.press_sequentially(value,delay=40);app.wait_for_timeout(150)
 typefield('Aktivierungstoken',activation);typefield('Neues Passwort',b['password']);typefield('Passwort wiederholen',b['password']);app.get_by_role('button',name='Aktivieren',exact=True).click()
 expect(app.get_by_role('button',name='Anmelden',exact=True)).to_be_visible();typefield('Benutzername',a['username']);typefield('Passwort',a['password']);app.get_by_role('button',name='Anmelden',exact=True).click();expect(app.get_by_text('Angemeldet als '+a['username']+' (Admin)',exact=True)).to_be_visible()
 app.get_by_role('button',name=re.compile('Meine Katalogbeiträge')).click();app.get_by_role('button',name='Öffentlichen Entwurf erstellen').click()
 typefield('Artikelnummer','M3-BROWSER-'+run);typefield('Bezeichnung',ui_name);typefield('Öffentliche Herkunft / Quellenangabe','Synthetische Browser-Abnahme, kein reales Produkt');typefield('Öffentliche Namensnennung','LibreECAD Testteam')
 app.get_by_role('checkbox',name=re.compile('Ich darf diese Daten')).click();expect(app.get_by_role('checkbox',name=re.compile('Ich darf diese Daten'))).to_be_checked();app.get_by_role('button',name='Als Entwurf speichern',exact=True).click();card=app.get_by_role('group',name=re.compile(re.escape('M3-BROWSER-'+run+' · '+ui_name)));expect(card).to_be_visible()
 card.get_by_role('button',name='Zur Prüfung einreichen',exact=True).click();typefield('Begründung (bei Rückzug öffentlich)','TEST: Browserfreigabe');app.get_by_role('button',name='Bewusst bestätigen',exact=True).click();expect(app.get_by_role('group',name=re.compile(re.escape(ui_name)+'.*In Prüfung · User-Upload'))).to_be_visible();app.screenshot(path='/tmp/libre-m3-contribution.png',full_page=True)
 page.get_by_role('button',name='Katalog & Moderation',exact=True).click();panel=page.locator('section.panel').filter(has=page.get_by_role('heading',name=ui_name,exact=True));expect(panel).to_be_visible();panel.get_by_role('button',name='Prüfen & Historie').click();expect(dlg.get_by_role('heading',name='Mögliche Duplikate')).to_be_visible();page.screenshot(path='/tmp/libre-m3-moderation.png',full_page=True)
 dlg.get_by_role('button',name='Freigeben',exact=True).click();dlg.get_by_label('Begründung / dokumentierter Vorgang').fill('TEST: synthetische öffentliche Vorschau geprüft');dlg.get_by_role('checkbox').check();dlg.get_by_role('button',name='Bestätigen',exact=True).click();expect(panel.get_by_text('Veröffentlicht',exact=True)).to_be_visible()
 app.get_by_role('button',name='Neu laden',exact=True).click();expect(app.get_by_role('group',name=re.compile(re.escape(ui_name)+'.*Veröffentlicht · User-Upload'))).to_be_visible()
 # Responsive view, isolated session and no external assets.
 page.set_viewport_size({'width':390,'height':844});page.get_by_role('button',name='Firmen & Zugänge',exact=True).click();expect(page.get_by_role('heading',name='Firmen & Zugänge')).to_be_visible();assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
 page.screenshot(path='/tmp/libre-m3-mobile.png',full_page=True)
 ui_token=page.evaluate('token');page.reload();expect(page.get_by_role('button',name='Als Superadmin anmelden')).to_be_visible()
 ctx.request.post(OP_WEB+'/api/auth/logout',headers={'Authorization':'Bearer '+ui_token})
 assert not errors,errors
 assert not external,external
 browser.close()
print('OK: LAN operator UI, two firms, audit, block/unblock, manufacturer revoke/grant, activation, Flutter contribution, moderation, responsive layout, no external requests or JS errors')
