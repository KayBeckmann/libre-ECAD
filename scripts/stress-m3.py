#!/usr/bin/env python3
"""Run after smoke-m3.py: overlapping database transactions and ordinary queries."""
import concurrent.futures,json,urllib.request
from pathlib import Path
s=json.loads(Path('/tmp/libre-ecad-m3-state.json').read_text());a=s['companies'][0]
def call(url,body=None,token=None):
 req=urllib.request.Request(url,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
 with urllib.request.urlopen(req,timeout=20) as r:assert r.status==200;return json.load(r)
co='http://127.0.0.1:8185/api/company';op='http://127.0.0.1:8186/api/operator';gl='http://127.0.0.1:8185/api/global'
token=call(co+'/auth/login',{'username':a['username'],'password':a['password']})['token']
def work(i):
 for _ in range(3):
  if i%5==0:call(op,{'action':'managed','operation':'users','companyId':a['id']},s['operatorToken'])
  elif i%5==1:call(op,{'action':'overview'},s['operatorToken'])
  elif i%5==2:call(co+'/me',token=token)
  elif i%5==3:call(co+'/api/v1/contributions',{'action':'list'},token)
  else:call(gl+'/articles?query=TEST')
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:list(pool.map(work,range(40)))
urllib.request.urlopen(urllib.request.Request(co+'/auth/logout',method='POST',headers={'Authorization':'Bearer '+token})).close()
print('OK: 120 overlapping authenticated queries and transactions across all three services, no connection errors')
