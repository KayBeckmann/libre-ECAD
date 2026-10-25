import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {Client} from '@modelcontextprotocol/client';
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio';

test('stdio discovery, exact API scope, pagination, proposals and safe errors',async()=>{
  const calls=[];
  const backend=createServer(async(req,res)=>{
    assert.equal(req.headers.authorization,'Bearer scoped-test');
    const chunks=[]; for await(const c of req) chunks.push(c);
    const body=chunks.length ? JSON.parse(Buffer.concat(chunks)):undefined;
    calls.push({path:req.url,body});
    res.setHeader('content-type','application/json');
    if(req.url.endsWith('/projects')) res.end(JSON.stringify({projects:[{id:'p',version:2},{id:'q',version:1}]}));
    else if(req.url.endsWith('/projects/p')) res.end(JSON.stringify({id:'p',version:2,drawing:{schemaVersion:1}}));
    else if(req.url.endsWith('/documents?version=2')) res.end(JSON.stringify({projectId:'p',version:2,data:{},findings:[]}));
    else if(req.url.endsWith('/proposals')) {res.statusCode=201;res.end(JSON.stringify({id:'proposal',status:'pending-human-review'}));}
    else {res.statusCode=403;res.end(JSON.stringify({error:'internal-secret-should-not-leak'}));}
  });
  await new Promise(resolve=>backend.listen(0,'127.0.0.1',resolve));
  const transport=new StdioClientTransport({command:process.execPath,args:['build/index.js'],env:{ECAD_BACKEND_URL:`http://127.0.0.1:${backend.address().port}`,ECAD_API_TOKEN:'scoped-test'}});
  const client=new Client({name:'acceptance',version:'1.0.0'});
  try {
    await client.connect(transport);
    const {tools}=await client.listTools();
    assert.deepEqual(tools.map(t=>t.name).sort(),['ecad_get_documents','ecad_get_project','ecad_list_projects','ecad_propose_drawing']);
    const call=async(name,args)=>client.callTool({name,arguments:args});
    const page=JSON.parse((await call('ecad_list_projects',{limit:1})).content[0].text);
    assert.equal(page.nextOffset,1);assert.equal(page.projects.length,1);
    const p=JSON.parse((await call('ecad_get_project',{projectId:'p'})).content[0].text);
    await call('ecad_get_documents',{projectId:'p',version:p.version});
    const proposal=JSON.parse((await call('ecad_propose_drawing',{projectId:'p',version:p.version,reason:'Review',drawing:p.drawing})).content[0].text);
    assert.equal(proposal.status,'pending-human-review');
    const denied=await call('ecad_get_project',{projectId:'foreign'});
    assert.equal(denied.isError,true);assert.match(denied.content[0].text,/ECAD 403/);assert.doesNotMatch(denied.content[0].text,/secret/);
    const before=calls.length;
    const invalid=await call('ecad_get_documents',{projectId:'p',version:-1});
    assert.equal(invalid.isError,true);assert.equal(calls.length,before);
    await assert.rejects(call('ecad_apply_proposal',{}),/not found/);
    assert.equal(calls.length,before);
    const traversal=await call('ecad_get_project',{projectId:'..'});
    assert.equal(traversal.isError,true);assert.equal(calls.length,before);
    assert(calls.every(c=>c.path.startsWith('/api/v1/automation/')));
  } finally {await client.close();await new Promise(resolve=>backend.close(resolve));}
});
