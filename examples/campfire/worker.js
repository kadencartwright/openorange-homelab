import { DurableObject } from "cloudflare:workers";
import page from "./page.js";
// Keep the original demo's class, binding and Wrangler name stable during upgrades.
export class Counter extends DurableObject {
  async increment() { const n = (await this.ctx.storage.get("count") ?? 0) + 1; await this.ctx.storage.put("count", n); return n; }
  async value() { return await this.ctx.storage.get("count") ?? 0; }
}
const json = (body, status = 200) => Response.json(body, { status, headers: { "cache-control": "no-store" } });
const rows = (cursor) => [...cursor];
const clean = (v, max) => typeof v === "string" ? v.trim().slice(0, max) : "";
const emojis = ["👍", "❤️", "🎉", "👀", "🔥"];

export class Workspace extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS channels (id TEXT PRIMARY KEY, description TEXT NOT NULL, created INTEGER NOT NULL)");
    for (const [id, description] of [["general", "The front porch of your home lab. Say hello."], ["builds", "Ship something small. Share what you’re making."], ["ideas", "A place for the next good idea."], ["random", "Everything that doesn’t need a ticket."]]) {
      ctx.storage.sql.exec("INSERT OR IGNORE INTO channels VALUES (?, ?, ?)", id, description, Date.now());
    }
  }
  async fetch(request) {
    if (request.method === "GET") return json(rows(this.ctx.storage.sql.exec("SELECT * FROM channels ORDER BY created, id")));
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
    const body = await request.json();
    const id = clean(body.id, 32).toLowerCase().replace(/\s+/g, "-");
    if (!/^[a-z][a-z0-9-]{0,31}$/.test(id)) return json({ error: "Use a channel name with letters, numbers and hyphens." }, 400);
    if (rows(this.ctx.storage.sql.exec("SELECT id FROM channels WHERE id = ?", id)).length) return json({ error: "That channel already exists." }, 409);
    if (rows(this.ctx.storage.sql.exec("SELECT count(*) AS n FROM channels"))[0].n >= 50) return json({ error: "This demo supports up to 50 channels." }, 400);
    const description = clean(body.description, 160) || "A fresh space for a new conversation.";
    const created = Date.now();
    this.ctx.storage.sql.exec("INSERT INTO channels VALUES (?, ?, ?)", id, description, created);
    return json({ id, description, created }, 201);
  }
}

export class Channel extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT UNIQUE NOT NULL, author_id TEXT NOT NULL, author TEXT NOT NULL, body TEXT NOT NULL, created INTEGER NOT NULL)");
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS reactions (message_id INTEGER NOT NULL, emoji TEXT NOT NULL, author_id TEXT NOT NULL, PRIMARY KEY(message_id, emoji, author_id))");
  }
  history(before) {
    const messages = rows(this.ctx.storage.sql.exec("SELECT * FROM messages WHERE id < ? ORDER BY id DESC LIMIT 100", before || Number.MAX_SAFE_INTEGER)).reverse();
    return messages.map((m) => ({ ...m, reactions: this.reactions(m.id) }));
  }
  reactions(id) {
    return rows(this.ctx.storage.sql.exec("SELECT emoji, author_id FROM reactions WHERE message_id = ? ORDER BY emoji, author_id", id));
  }
  send(ws, value) { try { ws.send(JSON.stringify(value)); } catch { /* disconnected */ } }
  broadcast(value) { for (const ws of this.ctx.getWebSockets()) this.send(ws, value); }
  presence() {
    const people = new Map();
    for (const ws of this.ctx.getWebSockets()) {
      if (ws.readyState !== 1) continue;
      try { const person = ws.deserializeAttachment(); if (person) people.set(person.id, { id: person.id, name: person.name }); } catch { /* closed */ }
    }
    this.broadcast({ type: "presence", people: [...people.values()] });
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (request.headers.get("Upgrade")?.toLowerCase() === "websocket") {
      const name = clean(url.searchParams.get("name"), 32);
      const id = clean(url.searchParams.get("user"), 80);
      if (!name || !/^[a-zA-Z0-9_-]{8,80}$/.test(id)) return json({ error: "Choose a display name first." }, 400);
      if (this.ctx.getWebSockets().length >= 100) return json({ error: "This channel is full." }, 429);
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ id, name, lastSent: 0 });
      this.send(server, { type: "init", messages: this.history() });
      this.presence();
      return new Response(null, { status: 101, webSocket: client });
    }
    if (request.method !== "GET") return json({ error: "Method not allowed" }, 405);
    const before = Number(url.searchParams.get("before"));
    return json({ messages: this.history(Number.isSafeInteger(before) && before > 0 ? before : undefined) });
  }
  async webSocketMessage(ws, raw) {
    let requestId;
    try {
      if (typeof raw !== "string" || raw.length > 12000) throw new Error("Message is too large.");
      const data = JSON.parse(raw);
      requestId = clean(data.clientId, 80);
      const person = ws.deserializeAttachment();
      if (data.type === "ping") return this.send(ws, { type: "pong" });
      if (data.type === "typing") return this.broadcast({ type: "typing", id: person.id, name: person.name });
      if (data.type === "message") {
        const body = clean(data.body, 4000);
        const clientId = clean(data.clientId, 80);
        if (!body || !/^[a-zA-Z0-9_-]{8,80}$/.test(clientId)) throw new Error("Enter a message of up to 4,000 characters.");
        const existing = rows(this.ctx.storage.sql.exec("SELECT * FROM messages WHERE client_id = ?", clientId))[0];
        if (existing) {
          if (existing.author_id !== person.id) throw new Error("Message ID is already in use.");
          return this.send(ws, { type: "message", message: { ...existing, reactions: this.reactions(existing.id) } });
        }
        if (Date.now() - person.lastSent < 300) throw new Error("Please slow down a little.");
        this.ctx.storage.sql.exec("INSERT INTO messages (client_id, author_id, author, body, created) VALUES (?, ?, ?, ?, ?)", clientId, person.id, person.name, body, Date.now());
        const message = rows(this.ctx.storage.sql.exec("SELECT * FROM messages WHERE client_id = ?", clientId))[0];
        ws.serializeAttachment({ ...person, lastSent: Date.now() });
        this.broadcast({ type: "message", message: { ...message, reactions: [] } });
        return;
      }
      if (data.type === "reaction") {
        if (!Number.isSafeInteger(data.id) || !emojis.includes(data.emoji)) throw new Error("Invalid reaction.");
        if (!rows(this.ctx.storage.sql.exec("SELECT id FROM messages WHERE id = ?", data.id)).length) throw new Error("Message not found.");
        const current = rows(this.ctx.storage.sql.exec("SELECT emoji FROM reactions WHERE message_id = ? AND emoji = ? AND author_id = ?", data.id, data.emoji, person.id));
        if (current.length) this.ctx.storage.sql.exec("DELETE FROM reactions WHERE message_id = ? AND emoji = ? AND author_id = ?", data.id, data.emoji, person.id);
        else this.ctx.storage.sql.exec("INSERT INTO reactions VALUES (?, ?, ?)", data.id, data.emoji, person.id);
        this.broadcast({ type: "reaction", id: data.id, reactions: this.reactions(data.id) });
        return;
      }
      throw new Error("Unknown message type.");
    } catch (error) { this.send(ws, { type: "error", error: error.message || "Unable to process message.", clientId: requestId }); }
  }
  async webSocketClose(ws, code, reason) { ws.close(code, reason); this.presence(); }
  async webSocketError(ws) { try { ws.close(1011, "Connection error"); } catch {} this.presence(); }
}

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (request.headers.get("origin") && request.headers.get("origin") !== url.origin) return json({ error: "Cross-origin requests are disabled." }, 403);
      if (url.pathname === "/") return new Response(page, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer" } });
      if (url.pathname === "/favicon.ico") return new Response(null, { status: 204 });
      if (url.pathname === "/health") return json({ status: "ok", app: "campfire" });
      if (url.pathname === "/api/channels") return env.WORKSPACE.getByName("campfire").fetch(request);
      const match = url.pathname.match(/^\/api\/channels\/([a-z][a-z0-9-]{0,31})\/(messages|socket)$/);
      if (match) {
        const available = await env.WORKSPACE.getByName("campfire").fetch(new Request(url.origin + "/api/channels"));
        if (!(await available.json()).some((c) => c.id === match[1])) return json({ error: "Channel not found." }, 404);
        return env.CHANNELS.getByName(match[1]).fetch(request);
      }
      if (url.pathname.startsWith("/api/counter/") || /^\/[a-zA-Z0-9_-]+$/.test(url.pathname)) {
        const api = url.pathname.startsWith("/api/counter/");
        const name = decodeURIComponent(api ? url.pathname.slice(13) : url.pathname.slice(1)) || "home";
        const counter = env.COUNTERS.getByName(name);
        return json({ name, count: api && request.method === "GET" ? await counter.value() : await counter.increment(), runtime: "OpenOrange home lab" });
      }
      return json({ error: "Not found." }, 404);
    } catch { return json({ error: "Unable to process request." }, 400); }
  }
};
