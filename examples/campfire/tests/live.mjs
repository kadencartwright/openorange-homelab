import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import WebSocket from 'ws';
const origin = (process.env.BASE_URL || 'http://100.96.205.20:8080').replace(/\/$/, '');
const statePath = process.env.TEST_STATE || '/tmp/campfire-live-test.json';
const room = 'lab-tests';
const api = async (path, options) => {
  const r = await fetch(origin + path, options);
  assert.ok(r.ok, `${r.status} ${await (!r.ok ? r.text() : Promise.resolve(''))}`);
  return r.json();
};
if (process.argv.includes('--verify')) {
  const expected = JSON.parse(readFileSync(statePath));
  const history = await api(`/api/channels/${room}/messages`);
  const message = history.messages.find(m => m.client_id === expected.clientId);
  assert.equal(message?.body, expected.body);
  assert.ok(message.reactions.some(r => r.emoji === '🔥' && r.author_id === expected.user));
  const fresh = await connect('Restart check');
  assert.ok(fresh.initial.messages.some(m => m.client_id === expected.clientId));
  fresh.ws.close();
  console.log('PASS: message and reaction survived Worker restart; new WebSocket received persisted history');
  process.exit(0);
}
const created = await fetch(origin + '/api/channels', { method: 'POST', headers: {'Content-Type':'application/json', Origin:origin}, body:JSON.stringify({id:room,description:'Automated realtime delivery and persistence checks.'}) });
assert.ok([201,409].includes(created.status), `channel creation: ${created.status} ${await created.text()}`);
const badOrigin = await fetch(origin + '/api/channels', {headers:{Origin:'http://unrelated.example'}});
assert.equal(badOrigin.status, 403);
async function connect(name) {
  const id = randomUUID(), url = new URL(`/api/channels/${room}/socket`,origin);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'; url.searchParams.set('name',name); url.searchParams.set('user',id);
  const ws = new WebSocket(url,{origin,handshakeTimeout:15000}); const inbox=[], waiting=[];
  ws.on('message',raw=>{const data=JSON.parse(String(raw));const at=waiting.findIndex(w=>w.test(data));if(at>=0){const w=waiting.splice(at,1)[0];clearTimeout(w.timer);w.resolve(data);}else inbox.push(data);});
  const next=(test)=>{const at=inbox.findIndex(test);if(at>=0)return Promise.resolve(inbox.splice(at,1)[0]);return new Promise((resolve,reject)=>{const w={test,resolve,timer:setTimeout(()=>{const i=waiting.indexOf(w);if(i>=0)waiting.splice(i,1);reject(new Error('Timed out awaiting event'));},15000)};waiting.push(w);});};
  await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);});
  const initial=await next(d=>d.type==='init');
  return {id,ws,initial,next,send:data=>ws.send(JSON.stringify(data))};
}
const a=await connect('Delivery check A'), b=await connect('Delivery check B');
try {
  await a.next(d=>d.type==='presence'&&d.people.some(p=>p.id===b.id));
  const clientId=randomUUID(),body='Live delivery check '+new Date().toISOString()+' <b>literal text</b>';
  a.send({type:'message',clientId,body});
  const received=await b.next(d=>d.type==='message'&&d.message.client_id===clientId);
  assert.equal(received.message.author,'Delivery check A');assert.equal(received.message.body,body);
  await a.next(d=>d.type==='message'&&d.message.client_id===clientId);
  a.send({type:'message',clientId,body});
  await a.next(d=>d.type==='message'&&d.message.client_id===clientId);
  const history=await api(`/api/channels/${room}/messages`);
  assert.equal(history.messages.filter(m=>m.client_id===clientId).length,1);
  b.send({type:'reaction',id:received.message.id,emoji:'🔥'});
  const reaction=await a.next(d=>d.type==='reaction'&&d.id===received.message.id);
  assert.ok(reaction.reactions.some(r=>r.author_id===b.id&&r.emoji==='🔥'));
  b.send({type:'typing'});await a.next(d=>d.type==='typing'&&d.id===b.id);
  const other=await api('/api/channels/general/messages');assert.ok(!other.messages.some(m=>m.client_id===clientId));
  const older=await api(`/api/channels/${room}/messages?before=${received.message.id}`);assert.ok(older.messages.every(m=>m.id<received.message.id));
  const missing=await fetch(origin+'/api/channels/does-not-exist/messages');assert.equal(missing.status,404);
  writeFileSync(statePath,JSON.stringify({clientId,body,user:b.id}));
  console.log('PASS: channel creation, origin checks, two-client delivery, presence, typing, deduplication, reactions, isolation, pagination and unknown-channel handling');
} finally {a.ws.close();b.ws.close();}
