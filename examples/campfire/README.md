# Campfire

A Slack-style chat demo running as an OpenOrange Worker, with SQLite-backed Durable Objects and hibernation-compatible WebSockets. No external chat service or database.

- Create channels with descriptions.
- Persistent channel history, with pagination for earlier messages.
- Realtime messages, online participants and typing indicators.
- Persistent emoji reactions; click again to remove your reaction.
- Reconnect with message-ID deduplication and retry of unacknowledged messages while the page remains open.
- Search the loaded conversation, responsive sidebar and keyboard composer.

The Workspace Durable Object stores the channel directory. Each Channel Durable Object owns its SQLite message/reaction tables and coordinates its connected WebSockets. WebSocket attachments retain display names and client IDs across object reinitialization. Presence and typing are transient; messages and reactions are persistent.

## Identity and scope

This is a shared, tailnet-only demo, with self-selected display names stored in browser local storage. Names are not verified. Everyone who can reach it can read channels, send messages, and create channels. It does not implement Slack accounts, channel permissions, DMs, threads, file uploads, or message editing/deletion. Messages are rendered as plain text.

The demo caps channel count at 50, connected sockets per channel at 100 and message length at 4,000 characters. History loads 100 messages at a time. Keep it on the existing private tailnet; production authentication and membership enforcement are outside this demo.

## Deployment on Bosgame

The `bosgame` flake selects `localhost/openorange-campfire:1` for its existing `hello` workload, on port 8080. Campfire deliberately keeps the Wrangler name `homelab-hello` and the original Counter class/binding, so the earlier counter data remains available through `/api/counter/NAME` and `/alice`. The chat UI replaces the counter landing page.

This single-Worker deployment also avoids a limitation in pinned OpenOrange 1.0.1: its primary runtime uses the `default` Rivet pool despite the container's `RIVET_POOL`. Do not assume two independent Orange containers on the same Engine are isolated just because their environment variables name different pools. A proper multi-Worker setup needs supported runtime pool routing.

Build on the controller:

```sh
bash scripts/build-worker.sh examples/campfire localhost/openorange-campfire:1
```

Import the image into the guest, update the host checkout and rebuild the `bosgame` VM closure, then restart `openorange-homelab-vm` on the Ubuntu host. See [Ubuntu hosting](../../docs/ubuntu-host.md). For future releases, change the image tag in the flake before rebuilding. The module preserves the application's external port in the upstream Host header so same-origin POST and WebSocket requests work through Nginx.

## Live checks

With the demo running:

```sh
cd examples/campfire
npm ci
BASE_URL=http://100.96.205.20:8080 npm run test:live
```

This creates/reuses the `lab-tests` channel and uses two actual WebSocket clients. It checks channel creation, origin validation, realtime delivery, presence, typing, deduplication, reactions, channel isolation, earlier-history pagination and missing-channel handling. It intentionally leaves its test message and reaction in that room.

After restarting the Worker, on the same test machine:

```sh
BASE_URL=http://100.96.205.20:8080 node tests/live.mjs --verify
```

The verifier reads `/tmp/campfire-live-test.json` and confirms the exact message and reaction survived. Override `TEST_STATE` to choose a different receipt path. HTTP and WebSocket checks do not substitute for browser interaction tests.
