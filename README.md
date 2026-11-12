# OpenOrange home lab

A NixOS flake for a dedicated **x86-64 UEFI mini PC** running [OpenOrange](https://github.com/rivet-dev/open-orange): Cloudflare-compatible Workers and Durable Objects on your own hardware. Includes Tailscale, SSH, Docker managed by systemd, a pinned Rivet Engine, persistent local storage, workload resource limits, an example Durable Object, installation and backup scripts.

This installs NixOS on bare metal. OpenOrange and Rivet use their upstream container deployment model on that host; the flake manages the OS and services. No Rivet Cloud account, Cloudflare account, external S3 service or Kubernetes cluster is required for the basic lab. Containers are fetched at runtime, so the first start needs internet. The Engine image is digest-pinned; Worker image pins are your choice.

## Layout and defaults

- Nixpkgs is pinned in `flake.lock`. `nixosConfigurations.minipc` is the complete OS; `nixosModules.openorange` is reusable.
- Hostname `orangebox`, administrator `lab`, UTC. SSH uses your key and accepts connections only through `tailscale0`. `lab` has passwordless sudo; don't add it to the Docker group.
- Tailscale needs interactive enrollment after the first boot. It advertises neither LAN routes nor an exit node. No router port forwarding is needed.
- Rivet Engine 3.1.2-rc.1 (matching OpenOrange 1.0.1’s bundled SDK) uses `/var/lib/openorange/log` and `/var/lib/openorange/objects`. The token is generated into a root-only directory on first start, outside Git and the Nix store.
- Each workload has its own Rivet pool, a local state directory, resource limits and a distinct Nginx port on the tailnet. Internal Worker listeners bind loopback. Engine ports 6420/6421 are blocked by the host firewall; Engine uses host networking, with no Docker published ports bypassing the firewall.
- Workloads run with host networking and the cluster token. Use this for **your trusted applications**; this is not a sandbox for arbitrary untrusted tenants. Rivet Engine listens on host interfaces behind the firewall.
- No workload runs until you add one. No unattended OS or image updates.

One machine has one copy of its data: this is a home lab, not a highly available cluster. Use off-box backups. Suggested starting hardware: 4 CPU cores, 8 GiB RAM (16 preferred), SSD/NVMe, wired Ethernet. These are sizing suggestions, not upstream minimums. Rivet requires at least 10% free disk space and at least 4 GiB free. Engine defaults here reserve at most 2 GiB RAM / 2 CPUs; each Worker defaults to 2 GiB / 2 CPUs. Leave memory for the OS and increase limits after measuring your workloads.

## Install on the mini PC

1. Back up the mini PC. Boot a current **NixOS x86-64 installer USB in UEFI mode**, with Secure Boot disabled. Connect Ethernet (or configure networking from the installer). Have your SSH **public** key on the USB or otherwise available there.
2. Clone this private repo in the installer. Install the clone tools with `nix-shell -p git gh`, then authenticate GitHub on that machine using your preferred method (`gh auth login` with HTTPS, `gh auth setup-git`, then `gh repo clone kadencartwright/openorange-homelab`). Do not put a token in a clone URL. A downloaded repository archive must be initialized with `git init && git add .` before using the flake.
3. Edit `hosts/minipc/settings.json` if you want a different hostname or time zone. Inspect the actual disk with `lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS`; prefer its `/dev/disk/by-id/…` path.
4. From the repository run:

   ```sh
   nix --extra-experimental-features 'nix-command flakes' develop
   sudo --preserve-env=PATH bash scripts/install.sh \
     /dev/disk/by-id/YOUR-INSTALL-DISK /path/to/id_ed25519.pub
   ```

The installer displays the resolved disk and requires you to type `ERASE /dev/…`. It erases the whole selected disk, creates a 1 GiB EFI partition and ext4 root, generates the real hardware configuration and installs the flake. It refuses mounted disks and active swap. It asks you to set a local console password for `lab`; SSH password authentication remains disabled. It does not encrypt the disk. There is no swap partition.

5. Reboot, remove the USB, log in as `lab` **at the physical console**, and run:

   ```sh
   sudo tailscale up
   ```

   Open the printed login URL on another device and approve the box in your tailnet. Then connect from a tailnet device with `ssh lab@orangebox` (or its `100.x.y.z` address if MagicDNS is off). Tailnet policy must allow TCP 22 and your selected workload ports; a narrow example grant is in [docs/tailscale.md](docs/tailscale.md).
6. The installed repository is `/etc/nixos/openorange`. Commit its generated `hardware-configuration.nix` and `settings.json` back to your private repo before managing it from another checkout. These contain hardware information and your **public** key, never private keys. The console password is not stored in the repo.

Do not use the checked-in placeholder hardware configuration to overwrite an existing machine remotely. The installer must generate the actual mounts, UUIDs and kernel modules. ARM, legacy BIOS, disk encryption, RAID and Wi-Fi-specific hardware need configuration changes before installation.

## Build and add a Worker

On the mini PC (or an x86-64 Linux build machine with Node 22+ and Docker), build the included example. Docker access is root-equivalent; use sudo on the mini PC:

```sh
cd /etc/nixos/openorange
nix develop
sudo --preserve-env=PATH bash scripts/build-worker.sh examples/hello localhost/openorange-hello:1
```

The script uses the example's committed npm lock, installs dependencies, runs `orange deploy --dry-run` without signing in, and builds its generated Dockerfile. Existing Workers can use the same script after adding `open-orange@1.0.1`, installing their own dependencies and committing `package-lock.json`. An immutable tag or registry digest is preferred for each release. If you built elsewhere, push to your registry (configure root's Docker credentials on the box for private images), or transfer a `docker save` archive and run `sudo docker load -i IMAGE.tar`.

Add this to `hosts/minipc/default.nix`, inside the final configuration attribute set:

```nix
services.openorange.workloads.hello = {
  image = "localhost/openorange-hello:1";
  port = 8080;
  internalPort = 18080;
  memory = "2g";
  cpus = "2";
  # Optional, root-owned mode 0600, KEY=value lines, not a Nix path:
  # environmentFile = "/var/lib/openorange/secrets/hello.env";
};
```

Then apply locally:

```sh
sudo bash scripts/rebuild.sh
sudo bash scripts/health.sh
curl http://127.0.0.1:8080/alice
```

From another tailnet device: `curl http://orangebox:8080/alice`. The returned `count` increases and should survive a reboot. Add other workloads with unique names and public/internal ports. The module creates each pool before starting its Worker. Keep the Worker's Wrangler name and pool stable between releases so its Durable Objects retain their identities. Do not share a pool between unrelated applications.

The proxy uses HTTP inside Tailscale's encrypted network. It does not publish anything to the internet. If you later add Tailscale Serve, configure its HTTPS proxy explicitly; Funnel is not enabled by this project. Use an SSH tunnel for local administration of the Engine API:

```sh
ssh -L 6420:127.0.0.1:6420 lab@orangebox
```

Application secrets go in the root-owned workload env file, not `vars` in Wrangler (which enter the image), Nix strings, Git or build arguments. The module supplies `RIVET_TOKEN`, `RIVET_ENDPOINT`, `RIVET_NAMESPACE` and `RIVET_POOL` and `RIVET_NODE_VERSION`; do not override them in your env file. Apply a new image tag to redeploy. Changing a runtime env file alone needs `sudo systemctl restart docker-orange-hello`.

## Operations

```sh
sudo journalctl -u docker-rivet -u openorange-pools -u docker-orange-hello -f
sudo bash scripts/health.sh
sudo nixos-rebuild switch --rollback   # OS/config rollback; NOT a data rollback
```

For a Worker rollback, restore its previous immutable image reference and rebuild. Keep older images until the rollback window passes. Do not prune images during a deployment. Engine data-format upgrades may prevent a binary downgrade: back up before updating its image. OS changes are applied manually; keep a known-good boot generation. Flake updates are explicit (`nix flake update`, review, `nix flake check`, rebuild). Updating the flake does not change the Engine digest or the example's npm lock. Do not run unattended `npm audit fix --force` against this early upstream release.

### Backup and restore

Mount an off-box backup destination, then:

```sh
sudo bash scripts/backup.sh /mnt/offbox-backups
```

This stops active Workers, then the Engine, archives **all** `/var/lib/openorange` (including recent-write logs, object data, Worker caches and tokens), creates a checksum, and restarts previously active services even on failure. Expect downtime while Workers drain (up to 30 minutes). Archives contain secrets: use an encrypted backup destination and restricted access. Check the command's exit status and monitor free space. No automatic backup schedule is enabled until you provide a destination. Back up separate workload environment files too if you placed them outside this directory, plus your Git config and any external application data.

To restore on a configured replacement host with the same image versions, keep it isolated from clients, stop Workers and Engine, and verify the checksum (`sha256sum -c FILE.sha256`). Move the existing `/var/lib/openorange` aside. Restore with `sudo tar --acls --xattrs --numeric-owner -C /var/lib -xzf FILE.tar.gz`, then `sudo systemctl restart openorange-secrets`, start `docker-rivet`, restart `openorange-pools` and start your Worker units. Never merge an old archive into a running Engine. Never run two live Engines from a copy of the same storage. Re-enroll Tailscale separately; its device identity is not in these backups. Test a restore periodically.

## Validation and upstream

`nix flake check` evaluates the NixOS configuration, checks the example workload's module wiring/firewall settings and runs ShellCheck on setup scripts. GitHub Actions repeats these checks. This does not replace testing on your own hardware. See [VALIDATION.md](VALIDATION.md) for what was actually run during repository creation.

Sources reviewed November 12, 2026:

- [Announcement](https://rivet.dev/changelog/2026-11-12-introducing-openorange/)
- [OpenOrange self-hosting](https://openorange.dev/docs/deploy/#self-host) and [source](https://github.com/rivet-dev/open-orange)
- [Rivet single-host Engine and local storage](https://rivet.dev/docs/deploy/self-host/control-plane/docker-compose/)
- [Worker nodes and pool setup](https://rivet.dev/docs/deploy/self-host/nodes/)

This repository supplies deployment configuration, not a fork of OpenOrange. Review upstream compatibility limitations for any Cloudflare bindings your workloads use.
