#!/usr/bin/env python3
"""Live M2 acceptance against the LAN stack; creates isolated synthetic test firms.
Run from repository root. Credentials are read from .env, never printed.
"""
import json
import os
import secrets
import urllib.error
import urllib.request
from pathlib import Path
from datetime import datetime

BASE = os.environ.get('LIBRE_ECAD_URL', 'http://127.0.0.1:8185')
config = dict(line.split('=', 1) for line in Path('.env').read_text().splitlines() if '=' in line and not line.startswith('#'))

def request(path, body=None, token=None, method=None, expected=200):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    assert response.code == expected, (path, response.code, raw.decode()[:400])
    return json.loads(raw) if raw else {}

super_token = request('/api/superadmin/auth/login', {'username': config['SUPER_ADMIN_BOOTSTRAP_USERNAME'], 'password': config['SUPER_ADMIN_BOOTSTRAP_PASSWORD']})['token']
stamp = datetime.now().strftime('%Y%m%d%H%M%S')

def company(suffix):
    company = request('/api/superadmin/companies', {'name': 'M2 Abnahme ' + stamp + ' ' + suffix}, super_token, expected=201)
    username = 'm2-' + stamp + '-' + suffix
    admin = request('/api/superadmin/companies/' + company['companyId'] + '/admins', {'username': username}, super_token, expected=201)
    password = secrets.token_urlsafe(18)
    request('/api/company/auth/activate', {'token': admin['activationToken'], 'password': password})
    token = request('/api/company/auth/login', {'username': username, 'password': password})['token']
    return company, token

company_a, a = company('A')
company_b, b = company('B')
P = '/api/company/api/v1/'
pa = request(P+'projects', {'name':'Identischer Projektname'}, a, expected=201)
pb = request(P+'projects', {'name':'Identischer Projektname'}, b, expected=201)
assert len(request(P+'projects', token=a)['projects']) == 1
request(P+'projects/'+pb['id'], token=a, expected=404)
request(P+'projects/'+pb['id'], {'name':'fremd','version':1}, a, method='PATCH', expected=404)
created = request('/api/company/users', {'username':'m2-'+stamp+'-zeichner'}, a, expected=201)
password = secrets.token_urlsafe(18)
request('/api/company/auth/activate', {'token':created['activationToken'],'password':password})
z = request('/api/company/auth/login', {'username':'m2-'+stamp+'-zeichner','password':password})['token']
request(P+'projects/'+pa['id'], token=z, expected=404)
pa = request(P+'projects/'+pa['id'], {'name':'Mit Mitglied','memberIds':[created['userId']],'version':1}, a, method='PATCH')
request(P+'projects/'+pa['id'], token=z)
request(P+'projects/'+pa['id'], {'name':'Stale','version':1}, a, method='PATCH', expected=409)
pa = request(P+'projects/'+pa['id'], {'name':'Mitglied entzogen','memberIds':[],'version':2}, a, method='PATCH')
request(P+'projects/'+pa['id'], token=z, expected=404)
print('PASS: tenant isolation, membership grant/revoke and version conflict (PostgreSQL).')

article = {'scope':'personal','articleNumber':'M2-SYNTH-16','name':'Synthetisches M2-Testgerät',
           'origin':'Eigener Abnahmetest','license':'CC0','layers':{
               'symbol':{'reference':'Testblock','license':'CC0','terminals':[{'id':'L','label':'L'}]},
               'mechanical':{'widthMm':18},'electrical':{'currentA':16},'thermal':{'powerLossW':0}}}
original = request(P+'articles', article, a, expected=201)
request(P+'articles/'+original['id'], token=z, expected=404)
request(P+'articles/'+original['id']+'/history', token=b, expected=404)
copy = request(P+'articles/'+original['id']+'/copy', {'scope':'company','version':1}, a, expected=201)
assert copy['source']['articleId'] == original['id'] and copy['id'] != original['id']
request(P+'articles/'+copy['id'], token=z)
request(P+'articles/'+copy['id'], {**article,'version':1}, z, method='PATCH', expected=403)
changed = request(P+'articles/'+original['id'], {**article,'name':'Version zwei','version':1}, a, method='PATCH')
assert changed['layers']['symbol']['id'] == original['layers']['symbol']['id']
assert len(request(P+'articles/'+original['id']+'/history',token=a)['versions']) == 2
assert request(P+'articles/'+copy['id'],token=a)['name'] == original['name']
request(P+'articles/'+original['id']+'/copy', {'scope':'company','version':1}, a, expected=409)
assert len(request(P+'articles?scope=company&query=SYNTH',token=a)['articles']) == 1
print('PASS: personal/company ACL, version history, copy provenance and separate search (PostgreSQL).')

hits = request('/api/global/articles?query=Beispieldaten&source=manufacturer&manufacturer=ACME')['results']
assert len(hits)==1 and hits[0]['manufacturerName']=='ACME'
hit=hits[0]
imported=request(P+'global-articles/'+hit['id']+'/copy',{'scope':'personal','version':hit['version']},a,expected=201)
assert imported['source']['kind']=='global' and imported['layers']['electrical']['voltageV'] is None
request('/api/company/users/'+created['userId'],{'active':False},a,method='PATCH')
request(P+'articles',token=z,expected=401)
print('PASS: filtered global search, deliberate import, missing technical data and session revocation.')
# Only transient local test state; never commit tokens.
state=Path('/tmp/libre-ecad-m2-smoke-state.json')
fd=os.open(state,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as file:
    json.dump({'token':a,'project':pa,'original':changed,'copy':copy,'imported':imported,'companyId':company_a['companyId']},file)
request('/api/superadmin/auth/logout',token=super_token,method='POST',expected=204)
print('PASS: live M2 acceptance complete; synthetic firms:', company_a['name'], '/', company_b['name'])
