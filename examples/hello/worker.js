import { DurableObject } from "cloudflare:workers";
export class Counter extends DurableObject {
  async increment() {
    const count = (await this.ctx.storage.get("count") ?? 0) + 1;
    await this.ctx.storage.put("count", count);
    return count;
  }
}
export default {
  async fetch(request, env) {
    const name = new URL(request.url).pathname.slice(1) || "home";
    const count = await env.COUNTERS.getByName(name).increment();
    return Response.json({ name, count, runtime: "OpenOrange home lab" });
  }
};
