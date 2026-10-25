#!/usr/bin/env python3
"""M7 persistence, tenant/CAS and moderated macro acceptance with synthetic data."""
import base64, importlib.util, json, os, random, struct, subprocess, time, zlib
from pathlib import Path
spec = importlib.util.spec_from_file_location('m4', Path(__file__).with_name('smoke-m4.py'))
m4 = importlib.util.module_from_spec(spec); spec.loader.exec_module(m4)
r, P = m4.request, m4.P

def main():
    old = json.loads(Path('/tmp/libre-ecad-m4-state.json').read_text())
    a,b = old['a'],old['b']
    for u in [a,b]:
        u['token'] = r('/api/company/auth/login', {'username':u['username'],'password':u['password']})['token']
    fixture = json.loads(subprocess.check_output(['dart','run','bin/planning_sample.dart'],cwd=m4.ROOT/'backend/ecad_core'))
    d = fixture['project']['drawing']; stamp=str(time.time_ns())
    # Exercise real proxy/body limits with a valid PNG larger than the old 128 KiB cap.
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rng=random.Random(7)
    pixels=b''.join(b'\0'+rng.randbytes(256*3) for _ in range(256))
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256,256,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
    large=json.loads(json.dumps(d));large['plans'][0]['background']['png']=base64.b64encode(png).decode()
    assert len(json.dumps(large))>131072
    probe=r(P+'projects',{'name':'TEST M7 Bildgroesse '+stamp},a['token'],expected=201)
    r(P+'projects/'+probe['id']+'/drawing',{'version':1,'drawing':large},a['token'],method='PUT')
    assert r(P+'projects/'+probe['id']+'/drawing',token=a['token'])['drawing']==large
    project=r(P+'projects',{'name':'TEST M7 Installation '+stamp},a['token'],expected=201)
    path=P+'projects/'+project['id']
    r(path+'/drawing',{'version':1,'drawing':d},a['token'],method='PUT')
    assert r(path+'/drawing',token=a['token'])['drawing']==d
    r(path+'/drawing',token=b['token'],expected=404)
    packet=r(path+'/documents?version=2',token=a['token'])
    pdf=base64.b64decode(packet['pdf']);assert pdf.startswith(b'%PDF')
    Path('/tmp/libre-m7-live.pdf').write_bytes(pdf)
    assert b'800' in subprocess.check_output(['pdfimages','-list','/tmp/libre-m7-live.pdf'])
    body={'scope':'personal','name':'TEST M7 Makro '+stamp,'origin':'Synthetischer eigener Test','license':'CC0-1.0','groups':['TEST','Installation'],'drawing':d}
    macro=r(P+'macros/',body,a['token'],expected=201)
    r(P+'macros/'+macro['id'],token=b['token'],expected=404)
    changed=r(P+'macros/'+macro['id'],{**body,'name':body['name']+' V2','version':1},a['token'],method='PATCH')
    r(P+'macros/'+macro['id'],{**body,'version':1},a['token'],method='PATCH',expected=409)
    assert len(r(P+'macros/'+macro['id']+'/history',token=a['token'])['versions'])==2
    copy=r(P+'macros/'+macro['id']+'/copy',{'scope':'company','version':2},a['token'],expected=201)
    assert copy['source']['id']==macro['id'] and copy['drawing']==d
    # A second company cannot access either scope.
    r(P+'macros/'+copy['id'],token=b['token'],expected=404)
    contrib=P+'contributions'
    draft=r(contrib,{'action':'create','source':'userUpload','rightsConfirmed':True,'payload':{'kind':'macro','articleNumber':'TEST-MACRO-'+stamp,'attribution':'Eigener Test',**{k:body[k] for k in ['name','origin','license','groups','drawing']}}},a['token'])
    def transition(v): return {'id':v['id'],'version':v['version'],'confirmed':True,'reason':'Synthetische M7-Abnahme'}
    assert not any(v['id']==draft['id'] for v in r(contrib,{'action':'publicMacros'},a['token'])['macros'])
    submitted=r(contrib,{'action':'submit',**transition(draft)},a['token'])
    op=r('/api/auth/login',{'username':m4.config['SUPER_ADMIN_BOOTSTRAP_USERNAME'],'password':m4.config['SUPER_ADMIN_BOOTSTRAP_PASSWORD']},operator=True)['token']
    approved=r('/api/operator',{'action':'catalog','operation':'approve',**transition(submitted)},op,operator=True)
    public=next(v for v in r(contrib,{'action':'publicMacros'},a['token'])['macros'] if v['id']==draft['id'])
    local=r(P+'macros/global/'+public['id']+'/copy',{'scope':'personal','version':public['version']},a['token'],expected=201)
    assert local['drawing']==d and local['source']['kind']=='global'
    r('/api/operator',{'action':'catalog','operation':'withdraw',**transition(approved)},op,operator=True)
    assert not any(v['id']==public['id'] for v in r(contrib,{'action':'publicMacros'},a['token'])['macros'])
    assert r(P+'macros/'+local['id'],token=a['token'])['drawing']==d
    r('/api/auth/logout',token=op,method='POST',expected=204,operator=True)
    out={'a':a,'projectId':project['id'],'projectName':project['name'],'macroId':macro['id'],'macroName':changed['name']}
    fd=os.open('/tmp/libre-ecad-m7-state.json',os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f:json.dump(out,f)
    print('PASS M7: persisted PNG/scale/routes/calculations/PLC channels and PDF; macro tenants, CAS, history, copies, public moderation and withdrawal')
if __name__=='__main__':main()
