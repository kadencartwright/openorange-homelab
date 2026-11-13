# Validation — November 12, 2026

Passed on the development machine:

- `nix flake check --print-build-logs`: complete base NixOS evaluation, example-workload wiring/firewall assertions, example OS derivation evaluation, ShellCheck on all setup scripts.
- `nix eval .#nixosConfigurations.minipc.config.system.build.toplevel.drvPath`: complete base OS derivation evaluates.
- Example `npm ci`, `orange deploy --dry-run` and the generated Docker image build on x86-64 Linux.
- Started the pinned Engine with local file-backed object storage, a generated admin token and a 2 GiB / 2 CPU limit. Created the `hello` pool through the authenticated API. Started the generated Worker with host networking, loopback HTTP binding, a state volume, dropped capabilities, no-new-privileges, and a 2 GiB / 2 CPU limit.
- Called `/alice`: durable count 1, then 2. Stopped the Worker, restarted Engine, started Worker: durable count 3. Removed the temporary test containers afterward.

The Engine image shown in the upstream quickstart (`3.0.1`) returned HTTP 500 to OpenOrange 1.0.1's bundled SDK. The configuration therefore pins **Engine 3.1.2-rc.1**, matching the bundled `rivetkit` version, by its Docker registry digest. This is a prerelease dependency; update Engine and OpenOrange together and retest. The generated Worker Dockerfile still uses upstream's mutable `node:24-slim` base. Build once and deploy an immutable image digest for repeatable rollout.

`npm audit` reported **12 dependency advisories (7 moderate, 5 high)** in the example's locked OpenOrange dependency tree, including transitive Wrangler/Miniflare, Undici, Zod and Sharp advisories. No forced upgrades or compatibility-breaking overrides were applied. Inspect `npm audit` when updating; keep this installation restricted to your tailnet and trusted applications.

Not performed for the initial bare-metal configuration: a full bare-metal system closure build, installation on the user's mini PC, actual Tailscale enrollment/policy validation, filesystem restore testing or a hardware power-loss test. The installer’s destructive partitioning commands were reviewed and linted, not run against a disk. Hardware, boot mode and networking must be verified during the physical installation. CI evaluates and lints; it does not claim hardware or runtime coverage.


## VM follow-up — November 12, 2026

- Built the complete `nixosConfigurations.vm.config.system.build.vm` closure and booted it with KVM on the development host: 4 vCPUs, 8 GiB RAM and a 40 GiB persistent root disk.
- Confirmed SSH key bootstrap, the read-only public-key share, Docker, Engine, pool creation, Nginx and the demo Worker. No failed systemd units.
- Built/imported the demo image through `scripts/vm.sh deploy-demo`. The same `alice` Durable Object returned count 1 before an orderly VM shutdown and 2 after restarting from the same disk, then 3 after deploying the web UI.
- Confirmed the root route serves the demo page, and counter API GET/POST/GET returned 0/1/1. Browser interactions were not automated; HTTP routes and returned page content were checked directly.
- The VM runner is managed by a systemd user service; state and management private key remain outside this repository.

- Enrolled the running VM in the user’s tailnet using browser approval. Verified the demo HTML and counter API from the host through the VM’s Tailscale IPv4 address, including a successful POST increment. The host resolver did not resolve the VM’s MagicDNS name, so the verified access URL uses its Tailscale IP.


## Ubuntu host deployment — November 13, 2026

- Recovered SSH access to `lab-bosgame` through its existing Kubernetes admin credentials. A temporary, time-limited maintenance pod appended the controller's existing GitHub public key to the Ubuntu `lab` account, backed up the prior authorized-keys file, and was deleted. Ansible ping over the host's Tailscale address then succeeded.
- Installed official, pinned Nix 2.35.3 in multi-user mode and built the complete `bosgame` VM closure on Ubuntu. No host OS replacement, disk formatting or host reboot.
- Shut down the original development VM before transferring its disk and management key over SSH. Source and destination SHA-256 checksums matched before expanding the virtual disk from 40 GiB to 56 GiB. Expanded ext4 in the guest; it reports approximately 55 GiB usable capacity.
- Booted the migrated VM on Bosgame with 12 vCPUs and 22 GiB assigned RAM. Confirmed the existing Tailscale identity and demo address survived. The `vm-demo` and `tailnet-demo` counters both retained their pre-migration value of 1.
- Verified the demo page and counter API over Tailscale after migration and after restarting the Ubuntu system service. Guest has no failed systemd units. The host's K3s control plane remained Ready and active; the temporary maintenance pod is gone.
- Installed/enabled `openorange-homelab-vm.service` as a system service. Tested its orderly stop/start via restart; the unit stopped successfully and returned active. A physical host reboot was not performed.
- Added a migration marker at the former development VM state directory so its helper refuses to start a second copy of the same Tailscale identity.
- `nix flake check` passes with both VM configurations and all setup scripts checked by ShellCheck.
