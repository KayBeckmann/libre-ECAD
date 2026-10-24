#!/usr/bin/env python3
"""M4 live acceptance. Creates synthetic firms; tokens stay in a mode-0600 temp file.
With --recovery also restarts the company service and tests pg_dump in a separate
throwaway database. No existing database is restored over or dropped.
"""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
WEB=os.environ.get('LIBRE_ECAD_URL','http://127.0.0.1:8185')
OP=os.environ.get('LIBRE_ECAD_OPERATOR_URL','http://127.0.0.1:8186')
P='/api/company/api/v1/'
config=dict(line.split('=',1) for line in (ROOT/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
def request(path,body=None,token=None,method=None,expected=200,operator=False):
    headers={'Content-Type':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    req=urllib.request.Request((OP if operator else WEB)+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
    try:response=urllib.request.urlopen(req,timeout=30)
    except urllib.error.HTTPError as e:response=e
    raw=response.read()
    if expected is not None:assert response.code==expected,(path,response.code,raw.decode()[:300])
    return (response.code,json.loads(raw) if raw else {}) if expected is None else (json.loads(raw) if raw else {})

def main():
    op=request('/api/auth/login',{'username':config['SUPER_ADMIN_BOOTSTRAP_USERNAME'],'password':config['SUPER_ADMIN_BOOTSTRAP_PASSWORD']},operator=True)['token']
    run=str(time.time_ns())
    def company(suffix):
        username='m4-'+run+'-'+suffix
        created=request('/api/operator',{'action':'managed','operation':'create','requestId':username,'name':'TEST M4 '+suffix+' '+run,'username':username,'confirmed':True,'reason':'TEST: isolated M4 acceptance'},op,operator=True)
        password=secrets.token_urlsafe(20)
        request('/api/company/auth/activate',{'token':created['activationToken'],'password':password})
        token=request('/api/company/auth/login',{'username':username,'password':password})['token']
        return {'id':created['id'],'username':username,'password':password,'token':token}
    a,b=company('A'),company('B')
    created=request('/api/company/users',{'username':'m4-'+run+'-drafter'},a['token'],expected=201)
    password=secrets.token_urlsafe(20)
    request('/api/company/auth/activate',{'token':created['activationToken'],'password':password})
    drafter=request('/api/company/auth/login',{'username':'m4-'+run+'-drafter','password':password})['token']
    samples=json.loads(subprocess.check_output(['dart','run','bin/samples.dart'],cwd=ROOT/'backend/ecad_core'))
    projects=[]
    for kind in ['distribution','motor']:
        project=request(P+'projects',{'name':'TEST M4 '+kind,'memberIds':[created['userId']]},a['token'],expected=201)
        path=P+'projects/'+project['id']+'/drawing'
        assert request(path,token=drafter)['drawing'] is None
        saved=request(path,{'version':1,'drawing':samples[kind]},drafter,method='PUT')
        assert saved['version']==2 and saved['drawing']==samples[kind]
        for suffix in ['', '/history', '/export']:
            request(path+suffix,token=b['token'],expected=404)
        request(path,{'version':2,'drawing':samples[kind]},b['token'],method='PUT',expected=404)
        request(path,{'version':1,'drawing':samples[kind]},a['token'],method='PUT',expected=409)
        broken=json.loads(json.dumps(samples[kind]));broken['instances'][0]['deviceId']='missing'
        request(path,{'version':2,'drawing':broken},a['token'],method='PUT',expected=400)
        assert request(path,token=a['token'])['version']==2
        # Two writers racing the same version: exactly one may succeed.
        with concurrent.futures.ThreadPoolExecutor() as pool:
            replies=list(pool.map(lambda _:request(path,{'version':2,'drawing':samples[kind]},a['token'],method='PUT',expected=None),range(2)))
        assert sorted(status for status,_ in replies)==[200,409]
        snapshot=request(path+'/export',token=a['token'])
        assert hashlib.sha256(snapshot['content'].encode()).hexdigest()==snapshot['sha256']
        assert snapshot==request(path+'/export',token=a['token'])
        # Git is only an archive of the exact immutable export, not a second writer.
        with tempfile.TemporaryDirectory(prefix='libre-m4-git-') as folder:
            subprocess.run(['git','init','-q',folder],check=True)
            file=Path(folder)/'project.json';file.write_bytes(snapshot['content'].encode('utf-8'))
            subprocess.run(['git','-C',folder,'add','project.json'],check=True)
            subprocess.run(['git','-C',folder,'-c','user.name=LibreECAD TEST','-c','user.email=test@example.invalid','commit','-qm','Synthetic M4 working snapshot'],check=True)
            recovered=subprocess.check_output(['git','-C',folder,'show','HEAD:project.json'])
            assert hashlib.sha256(recovered).hexdigest()==snapshot['sha256']
            def normalized(value):
                if isinstance(value,dict):return {k:normalized(v) for k,v in value.items()}
                if isinstance(value,list):
                    if value and all(isinstance(v,dict) and 'id' in v for v in value):value=sorted(value,key=lambda v:v['id'])
                    return [normalized(v) for v in value]
                return value
            assert normalized(json.loads(recovered)['drawing'])==normalized(samples[kind])
        projects.append({'id':project['id'],'kind':kind,'version':3,'snapshot':snapshot})
    path=P+'projects/'+projects[0]['id']
    request(path,{'name':'TEST M4 distribution','memberIds':[],'version':3},a['token'],method='PATCH')
    request(path+'/drawing',{'version':4,'drawing':samples['distribution']},drafter,method='PUT',expected=404)
    request(path+'/drawing/history',token=drafter,expected=404)
    # Explicit content recovery creates a new version and preserves old entries.
    history=request(path+'/drawing/history',token=a['token'])['versions']
    old=history[0]['drawing']
    renamed=json.loads(json.dumps(old));renamed['devices'][0]['bmk']='TEST-RENAMED'
    request(path+'/drawing',{'version':4,'drawing':renamed},a['token'],method='PUT')
    recovered=request(path+'/drawing',{'version':5,'drawing':old},a['token'],method='PUT')
    assert recovered['version']==6 and recovered['drawing']==old
    versions=request(path+'/drawing/history',token=a['token'])['versions']
    assert versions[0]['drawing']==old and versions[-2]['drawing']==renamed
    assert len(versions)==5
    request('/api/company/users/'+created['userId'],{'active':False},a['token'],method='PATCH')
    request(P+'projects/'+projects[1]['id']+'/drawing',token=drafter,expected=401)
    if '--recovery' in sys.argv:
        recovery(a,projects)
    state={'run':run,'a':a,'b':b,'projects':projects}
    fd=os.open('/tmp/libre-ecad-m4-state.json',os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f:json.dump(state,f)
    request('/api/auth/logout',token=op,method='POST',expected=204,operator=True)
    print('PASS M4: two samples, two tenants, membership/revocation, malformed graph rejection, concurrent CAS, history, canonical export and Git round-trip')

def recovery(a,projects):
    compose=['docker','compose']
    def pg(args,**kw):return subprocess.run(compose+['exec','-T','company-users-db']+args,cwd=ROOT,check=True,**kw)
    before={p['id']:request(P+'projects/'+p['id']+'/drawing/export',token=a['token']) for p in projects}
    db='m4_restore_'+str(time.time_ns())
    sql="SELECT 'documents',count(*),md5(string_agg(document::text,'' ORDER BY company_id,kind,id)) FROM workspace_documents UNION ALL SELECT 'history',count(*),md5(string_agg(document::text,'' ORDER BY company_id,kind,id,version)) FROM workspace_history"
    original=pg(['psql','-U','company_users','-d','company_users','-Atc',sql],capture_output=True).stdout
    with tempfile.TemporaryFile() as backup:
        pg(['pg_dump','-U','company_users','-Fc','company_users'],stdout=backup)
        pg(['createdb','-U','company_users',db])
        try:
            backup.seek(0);pg(['pg_restore','-U','company_users','--no-owner','-d',db],stdin=backup)
            restored=pg(['psql','-U','company_users','-d',db,'-Atc',sql],capture_output=True).stdout
            assert original==restored
        finally:pg(['dropdb','-U','company_users',db])
    subprocess.run(compose+['restart','company-users-db','company-users-service'],cwd=ROOT,check=True,capture_output=True)
    for attempt in range(40):
        try:
            after={p['id']:request(P+'projects/'+p['id']+'/drawing/export',token=a['token']) for p in projects}
            assert before==after;break
        except (OSError,AssertionError):time.sleep(.5)
    else:raise AssertionError('Service failed to recover identical drawing exports')
    print('PASS M4 recovery: isolated pg_dump/restore matches all workspace documents and history; database/service restart preserves byte-identical exports')

if __name__=='__main__':main()
