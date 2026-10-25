// Called by scripts/smoke-m6.py with a disposable scoped credential, never a UI session.
import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/client';
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio';
const client=new Client({name:'live-acceptance',version:'1.0.0'});
try {
  await client.connect(new StdioClientTransport({command:process.execPath,args:['build/index.js'],env:{ECAD_API_TOKEN:process.env.ECAD_API_TOKEN,ECAD_BACKEND_URL:process.env.ECAD_BACKEND_URL}}));
  async function call(name,args={}) { const r=await client.callTool({name,arguments:args});assert(!r.isError,JSON.stringify(r));return JSON.parse(r.content[0].text); }
  const list=await call('ecad_list_projects');assert.equal(list.projects.length,1);
  const project=await call('ecad_get_project',{projectId:list.projects[0].id});
  const docs=await call('ecad_get_documents',{projectId:project.id,version:project.version});assert(docs.data);
  const drawing=project.drawing;drawing.devices[0].label='TEST MCP proposal pending human review';
  const proposal=await call('ecad_propose_drawing',{projectId:project.id,version:project.version,reason:'TEST live stdio proposal',drawing});
  assert.equal(proposal.status,'pending-human-review');
  process.stdout.write(JSON.stringify(proposal));
} finally {await client.close();}
