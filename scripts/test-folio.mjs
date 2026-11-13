import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {writeFileSync,readFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
const origin=process.env.FOLIO_URL||'https://orangebox-vm.bleak-banana.ts.net', receipt='/tmp/folio-homelab-receipt.json', cookies='/tmp/folio-homelab-cookie';
if(process.argv.includes('--finish')){
 const saved=JSON.parse(readFileSync(receipt));const cookie=readFileSync(cookies,'utf8');
 const response=await fetch(origin+'/api/books/'+saved.id+'/download',{headers:{cookie}});
 assert.equal(response.status,200);assert.equal(createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex'),saved.id);
 const removed=await fetch(origin+'/api/books/'+saved.id,{method:'DELETE',headers:{cookie,Origin:origin}});assert.equal(removed.status,200);
 const out=await fetch(origin+'/api/auth/sign-out',{method:'POST',headers:{cookie,Origin:origin,'Content-Type':'application/json'},body:'{}'});assert.equal(out.status,200);
 console.log('PASS: 1 MiB book metadata and exact bytes survived Engine/Worker restart; fixture removed and session signed out');
 process.exit(0);
}
const output=execFileSync('ssh',[process.env.FOLIO_SSH_HOST||'lab@100.95.242.103','cd /home/lab/code/openorange-homelab; bash scripts/folio-login.sh'],{encoding:'utf8',timeout:60000});
const link=output.split('\n').find(line=>line.startsWith(origin+'/'));assert.ok(link,'Private login helper should return a link');
const signed=await fetch(link,{redirect:'manual'});assert.equal(signed.status,302);
const cookie=signed.headers.get('set-cookie')?.split(';')[0];assert.ok(cookie);writeFileSync(cookies,cookie,{mode:0o600});
const request=async(path,options={})=>fetch(origin+path,{...options,headers:{cookie,Origin:origin,...options.headers}});
assert.equal((await fetch(origin+'/api/books')).status,401);
assert.equal((await fetch(origin+'/api/local/mail')).status,404);
assert.equal((await fetch(origin+'/users/create',{method:'POST'})).status,404);
assert.equal((await request('/api/session')).status,200);
const bytes=Buffer.concat([Buffer.from('%PDF-1.7\n% Synthetic persistence fixture; removed after verification.\n'),Buffer.alloc(1024*1024,32),Buffer.from('\n%%EOF\n')]);
const uploaded=await request('/api/books',{method:'POST',headers:{'Content-Type':'application/pdf','x-filename':'homelab-persistence-check.pdf'},body:bytes});
assert.equal(uploaded.status,201,await uploaded.clone().text());const book=await uploaded.json();
assert.equal(book.id,createHash('sha256').update(bytes).digest('hex'));
const reader='smoke-'+Date.now(),password=randomUUID()+randomUUID();
try{
 const created=await request('/api/admin/accounts',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:reader,password})});assert.equal(created.status,201,await created.clone().text());
 const feed=await fetch(origin+'/opds/v1/catalog.xml',{headers:{Authorization:'Basic '+Buffer.from(reader+':'+password).toString('base64')}});assert.equal(feed.status,200);assert.ok((await feed.text()).includes(book.id));
 const downloaded=await fetch(origin+'/api/books/'+book.id+'/download',{headers:{Authorization:'Basic '+Buffer.from(reader+':'+password).toString('base64')}});assert.equal(downloaded.status,200);assert.deepEqual(Buffer.from(await downloaded.arrayBuffer()),bytes);
}finally{await request('/api/admin/accounts/'+reader,{method:'DELETE'});}
writeFileSync(receipt,JSON.stringify({id:book.id}),{mode:0o600});
console.log('PASS: private sign-in, protected catalog, blocked inbox/signup, 1 MiB upload/download, reader account, authenticated OPDS 1.2 and download; no credentials printed');
