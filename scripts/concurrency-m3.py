#!/usr/bin/env python3
"""Live last-admin race and session-revocation acceptance after smoke-m3.py."""
import json,secrets,urllib.request,urllib.error,concurrent.futures
from pathlib import Path
s=json.loads(Path('/tmp/libre-ecad-m3-state.json').read_text());a=s['companies'][0]
def call(url,body=None,token=None,method=None):
 try:r=urllib.request.urlopen(urllib.request.Request(url,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})},method=method),timeout=20)
 except urllib.error.HTTPError as e:r=e
 raw=r.read();return r.status,json.loads(raw) if raw else {}
def op(**b):
 code,d=call('http://127.0.0.1:8186/api/operator',b,s['operatorToken']);assert code==200,(code,d.get('error'));return d
base='http://127.0.0.1:8185/api/company'
other=op(action='managed',operation='addAdmin',companyId=a['id'],username='m3-race-'+s['run'],confirmed=True,reason='TEST: parallele Admin-Deaktivierung')
password=secrets.token_urlsafe(24)
assert call(base+'/auth/activate',{'token':other['activationToken'],'password':password})[0]==200
_,login=call(base+'/auth/login',{'username':a['username'],'password':a['password']});token=login['token']
users=op(action='managed',operation='users',companyId=a['id'])['users']
def deactivate(user):return call(base+'/users/'+user['id'],{'active':False},token,'PATCH')[0]
with concurrent.futures.ThreadPoolExecutor(2) as pool:codes=list(pool.map(deactivate,users))
assert codes.count(200)==1 and all(c in (200,403,409) for c in codes),codes
updated=op(action='managed',operation='users',companyId=a['id'])['users'];assert sum(u['active'] and u['activated'] for u in updated)==1
for u in updated:
 if not u['active']:op(action='managed',operation='userAccess',companyId=a['id'],userId=u['id'],version=u['version'],active=True,confirmed=True,reason='TEST: Ausgangszustand nach Paralleltest wiederherstellen')
# Old sessions for a disabled account must not revive. Explicitly deactivate/reactivate secondary admin.
_,otherlogin=call(base+'/auth/login',{'username':other['username'],'password':password});old=otherlogin['token']
u=next(u for u in op(action='managed',operation='users',companyId=a['id'])['users'] if u['id']==other['userId'])
op(action='managed',operation='userAccess',companyId=a['id'],userId=u['id'],version=u['version'],active=False,confirmed=True,reason='TEST: Sitzungswiderruf')
u=next(u for u in op(action='managed',operation='users',companyId=a['id'])['users'] if u['id']==other['userId'])
op(action='managed',operation='userAccess',companyId=a['id'],userId=u['id'],version=u['version'],active=True,confirmed=True,reason='TEST: Reaktivierung')
assert call(base+'/me',token=old)[0]==401
# Revoke test sessions and retain data/activation history.
call(base+'/auth/logout',token=token,method='POST')
print('OK: concurrent attempts retain one activated admin; disabled user sessions never revive after reactivation')
