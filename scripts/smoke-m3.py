#!/usr/bin/env python3
"""Live M3 acceptance. Creates clearly synthetic fixtures, never real payments.
Run against the local Compose stack. Secrets are only saved mode 0600 in /tmp
for optional browser acceptance and must be removed after that acceptance.
"""
import datetime
import json
import os
from pathlib import Path
import secrets
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
CONFIG = dict(line.split('=',1) for line in (ROOT/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
ACCESS = {'superadminUsername':CONFIG['SUPER_ADMIN_BOOTSTRAP_USERNAME'],'superadminPassword':CONFIG['SUPER_ADMIN_BOOTSTRAP_PASSWORD']}
OP = 'http://127.0.0.1:8186/api'
CO = 'http://127.0.0.1:8185/api/company'
GL = 'http://127.0.0.1:8185/api/global'
RUN = os.environ.get('M3_RUN_ID') or datetime.datetime.now().strftime('%Y%m%d%H%M%S')

def call(base, path, body=None, token=None, expected=200, method=None):
    request = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(), method=method or ('POST' if body is not None else 'GET'), headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {})})
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except urllib.error.HTTPError as e:
        response = e
    raw = response.read()
    assert response.status == expected, (path, response.status, expected, raw[:500] if response.status >= 400 else 'Unexpected success')
    if not raw: return {}
    try: return json.loads(raw)
    except json.JSONDecodeError:
        assert expected >= 400
        return {}

su = call(OP, '/auth/login', {'username': ACCESS['superadminUsername'], 'password': ACCESS['superadminPassword']})['token']
def op(action, expected=200, **kw):
    return call(OP, '/operator', {'action': action, **kw}, su, expected)
def managed(operation, expected=200, **kw):
    return op('managed', expected, operation=operation, **kw)
def catalog(operation, expected=200, **kw):
    return op('catalog', expected, operation=operation, **kw)
def user(token, action, expected=200, **kw):
    return call(CO, '/api/v1/contributions', {'action': action, **kw}, token, expected)
def transition(d):
    return {'id': d['id'], 'version': d['version'], 'confirmed': True, 'reason': 'TEST: dokumentierte M3-Abnahme'}
def payload(number):
    return {'articleNumber': number, 'name': 'TEST – M3 Katalogbeitrag', 'license': 'CC-BY-4.0', 'origin': 'Synthetische Abnahmedaten; kein reales Produkt', 'attribution': 'LibreECAD Testteam', 'notes': 'M3_PRIVATE_NEVER_GLOBAL', 'project': 'M3_PRIVATE_PROJECT', 'layers': {'electrical': {'voltageV': 0, 'currentA': 1}, 'thermal': {'powerLossW': None, 'conditions': 'TEST: keine Berechnungsfreigabe'}}}

fixtures = []
for letter in ['A', 'B']:
    username = 'm3-abnahme-' + letter.lower() + '-' + RUN
    request_id = 'm3-' + RUN + '-' + letter.lower()
    c = managed('create', requestId=request_id, name='M3 Abnahme ' + letter + ' – ' + RUN, username=username, confirmed=True, reason='TEST: synthetische Abnahmefirma')
    duplicate = managed('create', requestId=request_id, name='SHOULD NOT REPLACE', username=username, confirmed=True, reason='TEST: idempotent retry')
    assert duplicate['alreadyCreated'] and 'activationToken' not in duplicate
    if c.get('alreadyCreated'):
        existing = managed('users',companyId=c['id'])['users'][0]
        c.update(managed('activation',companyId=c['id'],userId=existing['id'],version=existing['version'],confirmed=True,reason='TEST: Abnahme erneut starten'))
    password = secrets.token_urlsafe(24)
    call(CO, '/auth/activate', {'token': c['activationToken'], 'password': password})
    call(CO, '/auth/activate', {'token': c['activationToken'], 'password': password}, expected=400)
    token = call(CO, '/auth/login', {'username': username, 'password': password})['token']
    fixtures.append({'id': c['id'], 'username': username, 'password': password, 'token': token, 'userId': c['userId']})
a, b = fixtures
print('OK: atomare Firmenanlage, zwei Admins, idempotente Wiederholung, einmalige Aktivierung')
# Existing company usernames must cause complete rollback, including new company.
managed('create', expected=409, requestId='rollback-'+RUN, name='MUST ROLLBACK', username=a['username'], confirmed=True, reason='TEST rollback')
assert not any(c['id']=='managed-rollback-'+RUN for c in managed('list')['companies'])
call(OP, '/operator', {'action': 'overview'}, a['token'], expected=401)
call(OP, '/operator', {'action': 'overview'}, expected=401)
call(CO, '/internal/operator/dispatch', {'action': 'list'}, a['token'], expected=404)
call('http://127.0.0.1:8183', '/internal/operator/dispatch', {'action': 'list'}, a['token'], expected=403)
call(GL, '/internal/contributions', {'action': 'list'}, a['token'], expected=404)
print('OK: Firmenadmin erreicht keine Betreiberrechte; interne Proxywege gesperrt; Anlagefehler rollt zurück')

op('contract', companyId=a['id'], status='trial', reference='TEST-VERTRAG-'+RUN, version=0, confirmed=True, reason='TEST: kein realer Vertrag')
pay = dict(companyId=a['id'], status='open', reference='TEST-BELEG-'+RUN, amountMinor=1234, currency='EUR', date='2026-10-24', confirmed=True, reason='TEST: synthetischer Beleg, keine reale Zahlung')
op('payment', id='payment-'+RUN, **pay)
op('payment', id='payment-b-'+RUN, **{**pay,'companyId':b['id'],'status':'failed','reference':'TEST-BELEG-B-'+RUN})
op('payment', id='correction-'+RUN, corrects='payment-'+RUN, **{**pay, 'status': 'success'})
op('payment', expected=409, id='double-correction-'+RUN, corrects='payment-'+RUN, **pay)
entries=op('overview')['payments'];assert any(e['id']=='payment-'+RUN and e['status']=='open' for e in entries)
ext='external-'+RUN
op('external', id=ext, name='TEST externer Betreiber', url='https://not-contacted.example.test', provider='TEST Provider', version=0, confirmed=True, reason='TEST: keine Fernsteuerung')
managed('access', expected=404, companyId=ext, version=1, active=False, confirmed=True, reason='TEST')
op('payment', expected=404, id='external-pay-'+RUN, **{**pay,'companyId':ext})
print('OK: manuelle Belege mit unveränderlichem Original und Korrektur; externe Backends bleiben getrennt')

managed('access', expected=400, companyId=a['id'], version=1, active=False, reason='TEST: missing confirmation')
managed('access', companyId=a['id'], version=1, active=False, confirmed=True, reason='TEST: Sperre und Benachrichtigungsprozess geprüft')
call(CO, '/me', token=a['token'], expected=401)
call(CO, '/auth/login', {'username':a['username'],'password':a['password']}, expected=403)
call(CO, '/me', token=b['token'])
managed('access', expected=409, companyId=a['id'], version=1, active=True, confirmed=True, reason='TEST stale')
managed('access', companyId=a['id'], version=2, active=True, confirmed=True, reason='TEST: Entsperrung')
call(CO, '/me', token=a['token'], expected=401)
a['token']=call(CO,'/auth/login',{'username':a['username'],'password':a['password']})['token']
users=managed('users',companyId=a['id'])['users']; admin=users[0]
managed('userAccess', expected=409, companyId=a['id'], userId=admin['id'], version=admin['version'], active=False, confirmed=True, reason='TEST last admin')
managed('userAccess', expected=404, companyId=b['id'], userId=admin['id'], version=admin['version'], active=False, confirmed=True, reason='TEST cross tenant')
assert len(managed('audit',companyId=a['id'])['entries'])>=3
print('OK: Sperre stoppt Anmeldung und Sitzungen; Entsperrung benötigt neuen Login; letzte Admins geschützt')

# Normal upload is never silently relabeled as manufacturer.
u=user(a['token'],'create',source='userUpload',rightsConfirmed=True,payload=payload('M3-TEST-USER-'+RUN),manufacturerName='ATTACK',mode='operator',actor={'userId':b['userId']})
assert u['source']=='userUpload' and u['manufacturerName'] is None
assert 'M3_PRIVATE' not in json.dumps(u)
call(GL,'/articles/'+u['id'],expected=404)
user(b['token'],'submit',expected=404,**transition(u))
u=user(a['token'],'submit',**transition(u))
catalog('approve',expected=400,**{**transition(u),'confirmed':False})
u=catalog('approve',**transition(u))
published=call(GL,'/articles/'+u['id']);assert published['source']=='userUpload' and published['version']==1
assert not any(k in published for k in ['owner','companyId','actor','evidence','notes'])
copy=call(CO,'/api/v1/global-articles/'+u['id']+'/copy',{'scope':'personal','version':1},a['token'],201)
assert copy['license']=='CC-BY-4.0' and copy['layers']['electrical']['voltageV']==0
# Public v1 must stay unchanged while v2 is under revision/review.
u=user(a['token'],'edit',**transition(u),rightsConfirmed=True,payload={**payload('M3-TEST-USER-'+RUN),'name':'TEST – überarbeitete Fassung'})
assert call(GL,'/articles/'+u['id'])['name']=='TEST – M3 Katalogbeitrag'
u=user(a['token'],'submit',**transition(u));u=catalog('approve',**transition(u))
assert call(GL,'/articles/'+u['id'])['version']==2
assert call(CO,'/api/v1/articles/'+copy['id'],token=a['token'])['source']['version']==1
hist=call(GL,'/articles/'+u['id']+'/history')['entries'];assert len(hist)==2 and 'companyId' not in json.dumps(hist)
print('OK: bewusste öffentliche Auswahl, Moderation, unveränderte Vorversion und lizenzierte unabhängige Kopie')

for f,letter in [(a,'A'),(b,'B')]:
    catalog('manufacturer',companyId=f['id'],name='TEST Hersteller '+letter+' '+RUN,active=True,evidence='TEST ONLY: synthetischer Identitätsnachweis '+letter,version=0,confirmed=True,reason='TEST: keine reale Herstellerprüfung')
user(a['token'],'create',expected=403,source='userUpload',rightsConfirmed=True,payload=payload('M3-TEST-NO-USER-RELABEL'))
m=user(a['token'],'create',source='manufacturer',manufacturerName='TEST Hersteller B '+RUN,rightsConfirmed=True,payload=payload('M3-TEST-MAKER-'+RUN))
assert m['manufacturerName']=='TEST Hersteller A '+RUN
m=user(a['token'],'submit',**transition(m));m=catalog('approve',**transition(m))
catalog('manufacturer',companyId=a['id'],name='TEST Hersteller A '+RUN,active=False,evidence='TEST ONLY: widerrufene synthetische Zuordnung',version=1,confirmed=True,reason='TEST: Entzug')
assert call(GL,'/articles/'+m['id'])['manufacturerName']=='TEST Hersteller A '+RUN
m=user(a['token'],'edit',**transition(m),rightsConfirmed=True,payload=payload('M3-TEST-MAKER-'+RUN))
user(a['token'],'submit',expected=403,**transition(m))
m=catalog('withdraw',**transition(m));call(GL,'/articles/'+m['id'],expected=404)
assert call(GL,'/articles/'+m['id']+'/history')['entries'][-1]['event']=='withdrawn'
assert not call(GL,'/articles?query=M3-TEST-MAKER-'+RUN)['results']
print('OK: Hersteller A kann Bereich B nicht bestimmen; Entzug stoppt neue Beiträge; Rückzug erhält Herkunft')

# Recovery invalidates earlier activation and sessions, then permits a new login.
admin=managed('users',companyId=b['id'])['users'][0]
recovery=managed('activation',companyId=b['id'],userId=admin['id'],version=admin['version'],confirmed=True,reason='TEST recovery')
call(CO,'/me',token=b['token'],expected=401)
call(CO,'/auth/activate',{'token':recovery['activationToken'],'password':b['password']})
b['token']=call(CO,'/auth/login',{'username':b['username'],'password':b['password']})['token']
state={'run':RUN,'operatorToken':su,'companies':fixtures,'userContribution':u,'manufacturerContribution':m,'externalId':ext}
path=Path('/tmp/libre-ecad-m3-state.json')
fd=os.open(path,os.O_CREAT|os.O_TRUNC|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as f:json.dump(state,f)
os.chmod(path,0o600)
print('OK: Wiederherstellung und erneute Aktivierung; Browser-Testzustand geschützt in /tmp gespeichert')
print('M3-Abnahme erfolgreich. Testfirmen: '+', '.join('M3 Abnahme '+x+' – '+RUN for x in ['A','B']))
