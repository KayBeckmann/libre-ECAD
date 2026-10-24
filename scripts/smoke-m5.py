#!/usr/bin/env python3
"""M5 integration acceptance against the dev stack; isolated TEST projects only."""
import base64, concurrent.futures, hashlib, importlib.util, json, os, secrets, subprocess, time
from pathlib import Path
spec=importlib.util.spec_from_file_location('m4',Path(__file__).with_name('smoke-m4.py'));m4=importlib.util.module_from_spec(spec);spec.loader.exec_module(m4)
r=m4.request;P=m4.P;ROOT=m4.ROOT
state=json.loads(Path('/tmp/libre-ecad-m4-state.json').read_text());a=state['a'];b=state['b']
for user in [a,b]: user['token']=r('/api/company/auth/login',{'username':user['username'],'password':user['password']})['token']
token=a['token'];run=str(time.time_ns())
samples=json.loads(subprocess.check_output(['dart','run','bin/samples.dart'],cwd=ROOT/'backend/ecad_core'))
created=r('/api/company/users',{'username':'m5-drafter-'+run},token,expected=201);pw=secrets.token_urlsafe(18)
r('/api/company/auth/activate',{'token':created['activationToken'],'password':pw});drafter=r('/api/company/auth/login',{'username':'m5-drafter-'+run,'password':pw})['token']
project=r(P+'projects',{'name':'TEST M5 '+run,'description':'Dokumentationsabnahme ÄÖÜ','metadata':{'Kunde':'TEST Kunde','Anlage':'TEST Motor','Dokumentnummer':'TEST-M5'},'memberIds':[created['userId']]},token,expected=201)
path=P+'projects/'+project['id'];r(path+'/drawing',{'version':1,'drawing':samples['motor']},token,method='PUT')
r(path+'/documents',token=token,expected=400)
doc=r(path+'/documents?version=2',token=token)
assert doc['data']['version']==doc['project']['version']==2
assert len(doc['data']['material'])==len(samples['motor']['devices'])
assert len(doc['data']['connections'])==len(samples['motor']['wires'])
assert doc['findings'] and all(f['objectId'] for f in doc['findings'])
for endpoint in ['/documents?version=2','/releases']:r(path+endpoint,token=b['token'],expected=404)
r(path+'/documents?version=2',token=drafter)
body={'version':2,'reason':'TEST: synthetic approval, not a real installation','confirmed':True,'exceptions':{f['id']:'TEST: deliberately open synthetic terminal' for f in doc['findings']}}
r(path+'/releases',body,drafter,method='POST',expected=403)
r(path+'/releases',{**body,'exceptions':{}},token,method='POST',expected=400)
r(path+'/releases',{**body,'confirmed':False},token,method='POST',expected=400)
r(path+'/releases',{**body,'version':1},token,method='POST',expected=409)
key=hashlib.sha256((a['id']+'/'+project['id']).encode()).hexdigest();archive='/var/lib/libre-ecad/archives/'+key+'.git'
def container(*args):return subprocess.check_output(['docker','compose','exec','-T','company-users-service',*args],cwd=ROOT)
# Only this newly-created test project: inject an unwritable archive path.
container('touch',archive)
try:
    r(path+'/releases',body,token,method='POST',expected=503)
    assert r(path+'/drawing',token=token)['version']==2
    assert r(path+'/releases',token=token)['releases']==[]
finally:container('rm',archive)
with concurrent.futures.ThreadPoolExecutor() as pool:
    replies=list(pool.map(lambda _:r(path+'/releases',body,token,method='POST',expected=None),range(2)))
assert sorted(status for status,_ in replies)==[201,409],replies
release=next(value['release'] for status,value in replies if status==201)
snapshot=r(path+'/documents?release='+release['id'],token=token)
pdf=base64.b64decode(snapshot['pdf']);assert hashlib.sha256(pdf).hexdigest()==release['sha256']
assert container('git','--git-dir='+archive,'show',release['commit']+':output.pdf')==pdf
manifest=json.loads(container('git','--git-dir='+archive,'show',release['commit']+':manifest.json'))
for name,digest in manifest['files'].items():assert hashlib.sha256(container('git','--git-dir='+archive,'show',release['commit']+':'+name)).hexdigest()==digest
Path('/tmp/libre-m5-approved.pdf').write_bytes(pdf)
text=subprocess.check_output(['pdftotext','/tmp/libre-m5-approved.pdf','-']).decode()
assert 'FACHLICH FESTGESCHRIEBEN' in text and 'TEST Kunde' in text and 'Klemmenliste' in text and 'Materialliste' in text
assert 'V2 |' in text and 'Keine Normprüfung' in text
# Later changes and a second release cannot mutate the approved source or PDF.
changed=json.loads(json.dumps(samples['motor']));changed['devices'][0]['label']='TEST subsequent change'
r(path+'/drawing',{'version':3,'drawing':changed},token,method='PUT')
assert r(path+'/documents?release='+release['id'],token=token)==snapshot
current=r(path+'/documents?version=4',token=token)
second=r(path+'/releases',{**body,'version':4,'exceptions':{f['id']:'TEST reviewed again for V4' for f in current['findings']}},token,method='POST',expected=201)['release']
assert container('git','--git-dir='+archive,'rev-parse',second['commit']+'^').decode().strip()==release['commit']
# Rename this synthetic archive; SQL-only evidence must reproduce both commits.
container('mv',archive,archive+'.testbackup')
try:
    rebuilt=r(path+'/documents?release='+second['id'],token=token)
    assert rebuilt['release']['commit']==second['commit']
    assert r(path+'/documents?release='+release['id'],token=token)==snapshot
finally:container('rm','-rf',archive+'.testbackup')
# Revocation applies to saved releases and PDF downloads as well.
r('/api/company/users/'+created['userId'],{'active':False},token,method='PATCH')
r(path+'/documents?release='+release['id'],token=drafter,expected=401)
m4.recovery(a,[{'id':project['id']}])
assert r(path+'/documents?release='+release['id'],token=token)==snapshot
out={'a':a,'projectId':project['id'],'release':release,'second':second}
fd=os.open('/tmp/libre-ecad-m5-state.json',os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as f:json.dump(out,f)
print('PASS M5: derived lists, metadata/PDF, object findings, tenant/role/revocation, missing-reason rejection, archive failure atomicity, racing approvals, immutable old PDF, real Git files/parent/hashes, SQL-only archive rebuild, DB backup/restore and restart')
