# Folio in the homelab

This deployment uses the cleaned public [Folio source](https://github.com/kadencartwright/opds-r2-library), pinned by revision in `source.json`, and OpenOrange 1.0.1. Application code is unchanged; the build adds an Orange CLI and a homelab Wrangler configuration.

Folio runs in the existing NixOS VM on Bosgame at **http://100.96.205.20:8081/**. Campfire remains on port 8080. This is an **independent, initially empty library**: no database, books, readers, credentials or sessions are copied from the Cloudflare installation. The existing cloud library is unchanged.

## Storage and isolation

- Its own Rivet Engine binds loopback ports 6440/6441 (with metrics on loopback 6450). This avoids the pinned runtime's default-pool collision between independent applications.
- D1 is backed by a SQLite Durable Object on this Engine. All six upstream migrations are applied automatically after Worker readiness; subsequent runs skip already applied migrations.
- R2 is backed by a separate Rivet Actor on the same Engine. It holds original ebooks and cover objects on the VM's local storage. There are no Cloudflare or S3 credentials in this deployment.
- `/var/lib/folio` in the guest holds Engine logs, objects, Worker state and generated root-only secrets. The authentication signing secret and Engine token persist across restarts and never enter Git or the Nix store.
- Worker HTTP binds loopback 18081; Nginx exposes 8081 only through the Tailscale interface. The Engine API is not exposed to the tailnet.

The default R2-on-Actor backend is suitable for trying the app and small collections. Large collections should use the supported S3 backend rather than placing an entire bucket in one Actor. Folio itself caps uploads at 16 MiB. This is not a migration of the public Cloudflare library or a backup of it.

## Sign in

No external email provider is configured. The app uses its supported simulated-email mode, with administrator bypass **disabled** and the administrator allowlist set to `admin@example.com`. You still need a valid, short-lived sign-in link to get an admin session.

The simulated inbox (`/api/local/mail`) and local mode's open reader-signup endpoint (`/users/create`) are blocked by Nginx on the tailnet-facing port. Access to the inbox requires VM administration over SSH. To generate a link, run on the Ubuntu host:

```sh
ssh lab@lab-bosgame
cd /home/lab/code/openorange-homelab
bash scripts/folio-login.sh
```

Open the printed private link within five minutes on a Tailscale-connected device. Treat it like a password; do not post it in chat, logs, screenshots or issues. The script requests a link and reads it through the guest's loopback-only listener. Once signed in, upload a book and create reader accounts under **Readers**.

For real email, configure an SMTP transport through OpenOrange's Email binding, set the actual sender/administrator, disable `LOCAL_DEV`, and use the library's intended HTTPS production setup. This first deployment does not silently reuse your cloud email configuration.

## Reader endpoints

After creating a reader account in the authenticated UI:

- OPDS 1.2: `http://100.96.205.20:8081/opds/v1/catalog.xml`
- OPDS 2.0: `http://100.96.205.20:8081/opds/v2/catalog.json`
- Reading sync: `http://100.96.205.20:8081`

Use these HTTP URLs only over the encrypted tailnet. Physical reader firmware and TLS behavior have not been tested in this deployment.

## Build, deploy and inspect

On the controller, with Node 24+, pnpm 11.20.0, Git, jq, and Docker:

```sh
bash scripts/build-folio.sh
```

The script checks out the pinned public commit in a temporary directory, installs its frozen dependencies, type-checks and builds the app, then generates an Orange Docker image. It does not run Alchemy deployment commands or access production D1/R2. Image metadata is recorded in `source.json`; update the revision and tag deliberately for releases.

Import the image into the guest, sync the homelab configuration to the Ubuntu host, build `.#nixosConfigurations.bosgame.config.system.build.vm`, and restart `openorange-homelab-vm`. The Folio module is imported only by the Bosgame configuration.

Inside the NixOS guest:

```sh
sudo systemctl status docker-folio-engine docker-folio folio-migrations
sudo journalctl -u docker-folio -u folio-migrations -f
```

A failed migration unit prevents a clean deployment; inspect it before serving the app. Do not wipe the database or storage volumes as a repair step.

## Backups

The earlier OpenOrange backup script covers Campfire, not this separate Engine. For Folio, mount an off-box destination in the guest and run:

```sh
sudo bash scripts/backup-folio.sh /mnt/offbox-backups
```

This stops Folio and its Engine, archives all of `/var/lib/folio` including its secrets and both storage tiers, creates a checksum, and restarts previously active units. It does not stop Campfire. Store archives encrypted and verify restores independently. An automatic backup schedule is not enabled because no destination has been supplied.
