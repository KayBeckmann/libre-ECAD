#!/usr/bin/env python3
"""Real SQL/HTTP and MCP stdio acceptance. Uses only synthetic M4 test company data."""
import concurrent.futures, importlib.util, json, os, subprocess, time, sys, tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('m4',Path(__file__).with_name('smoke-m4.py'));m4=importlib.util.module_from_spec(spec);spec.loader.exec_module(m4)
r=m4.request;ROOT=m4.ROOT;P=m4.P
state=json.loads(Path('/tmp/libre-ecad-m4-state.json').read_text());a=state['a'];b=state['b']
a['token']=r('/api/company/auth/login',{'username':a['username'],'password':a['password']})['token']
b['token']=r('/api/company/auth/login',{'username':b['username'],'password':b['password']})['token']
token=a['token']
project=r(P+'projects',{'name':'TEST M6 '+str(time.time_ns())},token,expected=201)
id=project['id'];path=P+'projects/'+id
samples=json.loads(subprocess.check_output(['dart','run','bin/samples.dart'],cwd=ROOT/'backend/ecad_core'))
r(path+'/drawing',{'version':1,'drawing':samples['motor']},token,method='PUT')
packet=r(path+'/offline',{'confirmed':True},token)
assert packet['baseVersion']==2 and 'token' not in packet
r(path+'/offline',{'confirmed':True},b['token'],expected=404)
r(path+'/offline',{},token,expected=400)
upload={'confirmed':True,'userId':packet['userId'],'companyId':packet['companyId'],'baseVersion':2,'version':2,'drawing':samples['distribution']}
r(path+'/offline/upload',{**upload,'userId':'foreign'},token,expected=403)
with concurrent.futures.ThreadPoolExecutor() as pool:
    replies=list(pool.map(lambda _:r(path+'/offline/upload',upload,token,expected=None),range(2)))
assert sorted(code for code,_ in replies)==[200,409]
issue={'confirmed':True,'projectIds':[id],'label':'TEST M6 scoped MCP','allowProposals':True}
t=r(P+'automation/tokens',issue,token,expected=201)
r(path,token=t['token'],expected=401)
r(path+'/releases',{'confirmed':True},t['token'],expected=401)
proposal=json.loads(subprocess.check_output(['node','test/live.mjs'],cwd=ROOT/'mcp',env={**os.environ,'ECAD_BACKEND_URL':m4.WEB+'/api/company','ECAD_API_TOKEN':t['token']}))
assert r(path,token=token)['version']==3
review=P+'automation/review/'+id
r(review+'/'+proposal['id']+'/apply',{'confirmed':True,'version':3},t['token'],expected=401)
r(review,token=b['token'],expected=404)
r(review+'/'+proposal['id']+'/apply',{'version':3},token,expected=400)
with concurrent.futures.ThreadPoolExecutor() as pool:
    replies=list(pool.map(lambda _:r(review+'/'+proposal['id']+'/apply',{'confirmed':True,'version':3},token,expected=None),range(2)))
assert sorted(code for code,_ in replies)==[200,409]
assert r(path,token=token)['activity']['proposalId']==proposal['id']
r(P+'automation/tokens/'+t['id']+'/revoke',{},token)
r(P+'automation/projects',token=t['token'],expected=401)
ro=r(P+'automation/tokens',{**issue,'allowProposals':False},token,expected=201)
r(P+'automation/projects/'+id+'/proposals',{'version':4,'drawing':samples['motor'],'reason':'forbidden'},ro['token'],expected=403)
r(P+'automation/tokens/'+ro['id']+'/revoke',{},token)
# Pending proposal for browser review acceptance; token revoked immediately afterward.
t=r(P+'automation/tokens',issue,token,expected=201)
pending=r(P+'automation/projects/'+id+'/proposals',{'version':4,'drawing':samples['motor'],'reason':'TEST browser comparison'},t['token'],expected=201)
r(P+'automation/tokens/'+t['id']+'/revoke',{},token)
fd=os.open('/tmp/libre-ecad-m6-state.json',os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as f:json.dump({'a':a,'projectId':id,'pending':pending},f)
# Restart persists scope revocations and immutable proposals in SQL.
subprocess.run(['docker','compose','restart','company-users-service'],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
for _ in range(60):
    try:
        if r('/api/company/health',expected=None)[0]==200:break
    except Exception:pass
    time.sleep(.5)
else:raise AssertionError('Service did not restart')
r(P+'automation/projects',token=t['token'],expected=401)
assert len(r(review,token=token)['proposals'])==2

if '--recovery' in sys.argv:
    def pg(args,**kwargs):return subprocess.run(['docker','compose','exec','-T','company-users-db',*args],cwd=ROOT,check=True,**kwargs)
    tables={'workspace_documents':'company_id,kind,id','workspace_history':'company_id,kind,id,version','m3_records':'kind,id','m3_history':'kind,id,version'}
    sql=' UNION ALL '.join("SELECT '"+t+"',count(*),md5(string_agg(document::text,'' ORDER BY "+order+")) FROM "+t for t,order in tables.items())
    original=pg(['psql','-U','company_users','-d','company_users','-Atc',sql],capture_output=True).stdout
    db='m6_restore_'+str(time.time_ns())
    with tempfile.TemporaryFile() as backup:
        pg(['pg_dump','-U','company_users','-Fc','company_users'],stdout=backup)
        pg(['createdb','-U','company_users',db])
        try:
            backup.seek(0);pg(['pg_restore','-U','company_users','--no-owner','-d',db],stdin=backup)
            assert original==pg(['psql','-U','company_users','-d',db,'-Atc',sql],capture_output=True).stdout
        finally:pg(['dropdb','-U','company_users',db])
    print('PASS M6 backup/restore: exact workspace and automation records/history in a separate temporary database')
if '--outage' in sys.argv:
    before=r(path,token=token)
    subprocess.run(['docker','compose','stop','global-articles-service'],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    try:
        assert r(path,token=token)==before
        assert r(path+'/offline',{'confirmed':True},token)['baseVersion']==before['version']
        r(P+'global-articles/sample/copy',{'scope':'personal','version':1},token,expected=503)
        assert r(path,token=token)==before
    finally:
        subprocess.run(['docker','compose','start','global-articles-service'],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    for _ in range(60):
        try:
            if r('/api/global/health',expected=None)[0]==200:break
        except Exception:pass
        time.sleep(.5)
    else:raise AssertionError('Global service did not recover')
    print('PASS M6 global outage: company project/prepare remain available, import fails closed, global service restored')
print('PASS M6 SQL/HTTP + real MCP stdio: tenant/scope, offline CAS, pending proposals, confirmation/CAS audit, read-only token, revoke and persistence')
