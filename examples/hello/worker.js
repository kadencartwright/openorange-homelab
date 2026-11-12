import { DurableObject } from "cloudflare:workers";

export class Counter extends DurableObject {
  async increment() {
    const count = (await this.ctx.storage.get("count") ?? 0) + 1;
    await this.ctx.storage.put("count", count);
    return count;
  }
  async value() {
    return await this.ctx.storage.get("count") ?? 0;
  }
}

const page = `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Orangebox · Durable counter</title>
<style>
:root{color-scheme:dark;font:17px system-ui;background:#141916;color:#eef3eb}
body{max-width:620px;margin:12vh auto;padding:24px}small{color:#bac4b7;letter-spacing:.12em}
h1{font-size:clamp(2rem,6vw,3rem);letter-spacing:-.04em;margin-bottom:16px}
p{line-height:1.6;color:#bac4b7}form{display:flex;gap:12px;flex-wrap:wrap;margin-top:32px}
label{display:block;width:100%;color:#bac4b7}input,button{font:inherit;padding:12px 16px;border-radius:10px;border:1px solid #4e5e4c}
input{background:#20271f;color:inherit;flex:1;min-width:160px}button{background:#ffb56b;color:#281608;cursor:pointer;font-weight:650}
button:disabled{opacity:.5}output{display:block;font-size:5rem;font-variant-numeric:tabular-nums;margin-top:24px}
#status{min-height:2em}footer{border-top:1px solid #344130;padding-top:24px;margin-top:32px;font-size:.85rem;color:#bac4b7}
</style><body><small>OPENORANGE / NIXOS / TAILSCALE</small>
<h1>A little state.<br>Your own server.</h1>
<p>This counter lives in a Durable Object on your home lab. Give it a name, increment it, and come back after a restart: its value stays.</p>
<form id="form"><label for="name">Counter name</label><input id="name" value="home" maxlength="100" required><button id="increment">Increment</button></form>
<output id="count" aria-live="polite">—</output><p id="status" role="status">Loading your counter…</p>
<footer>Each name gets its own Durable Object. Served by a Worker through your private tailnet.</footer>
<script>
const form=document.querySelector('#form'),nameInput=document.querySelector('#name'),count=document.querySelector('#count'),statusText=document.querySelector('#status'),button=document.querySelector('#increment');
async function update(method){button.disabled=true;try{const response=await fetch('/api/counter/'+encodeURIComponent(nameInput.value.trim()||'home'),{method});if(!response.ok)throw new Error('Request failed ('+response.status+')');const result=await response.json();count.textContent=result.count;statusText.textContent='Saved on orangebox · '+result.name;}catch(error){statusText.textContent=error.message;}finally{button.disabled=false;}}
form.addEventListener('submit',event=>{event.preventDefault();update('POST');});nameInput.addEventListener('change',()=>update('GET'));update('GET');
</script></body></html>`;

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/") return new Response(page, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
    const api = path.startsWith("/api/counter/");
    if (api && !["GET", "POST"].includes(request.method)) return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, POST" } });
    let name;
    try { name = decodeURIComponent(api ? path.slice(13) : path.slice(1)) || "home"; }
    catch { return new Response("Invalid counter name", { status: 400 }); }
    if (name.length > 100) return new Response("Counter name too long", { status: 400 });
    const counter = env.COUNTERS.getByName(name);
    const count = api && request.method === "GET" ? await counter.value() : await counter.increment();
    return Response.json({ name, count, runtime: "OpenOrange home lab" }, { headers: { "cache-control": "no-store" } });
  }
};
