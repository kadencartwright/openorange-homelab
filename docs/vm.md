# Run the demo in a local VM

The `vm` NixOS configuration reuses the bare-metal host and OpenOrange module. It adds a headless QEMU/KVM runner with 4 CPUs, 8 GiB RAM, and a persistent 40 GiB qcow2 disk. The VM is named `orangebox-vm`. It uses the host's Nix store read-only, so this runner depends on this development host; it is not a standalone disk image to copy to another machine.

On an x86-64 Linux host with KVM access and a running systemd user manager:

```sh
nix develop
bash scripts/vm.sh start
bash scripts/vm.sh deploy-demo
bash scripts/vm.sh ssh curl --fail http://127.0.0.1:8080/alice
```

The start script creates a dedicated SSH management key outside Git, builds the VM, and launches the `openorange-homelab-vm` systemd **user** service. Bootstrap SSH is forwarded only on the host's `127.0.0.1:22222`. The VM's NAT interface allows SSH for this forward; application access remains tailnet-only. This does not change the bare-metal firewall.

The default state directory is `~/.local/state/openorange-homelab-vm` (override with `OPENORANGE_VM_STATE_DIR`). Keep this directory: it contains the disk with your Tailscale enrollment, Engine data and Docker images, plus the private management key and SSH host-key pin. Do not commit it or run two VMs against one disk. A read-only share passes only the public key into the VM on boot.

## Join Tailscale

For interactive enrollment, run `bash scripts/vm.sh ssh sudo tailscale up`, open its login URL on your own device and approve `orangebox-vm`. Alternatively, enroll using a one-use non-ephemeral auth key supplied privately to your agent. Do not put the key in Git or a command argument; Tailscale supports `--auth-key=file:/root/PATH` for a temporary root-only key file. Remove that temporary file after enrollment.

Then:

```sh
bash scripts/vm.sh ssh tailscale ip -4
bash scripts/vm.sh ssh tailscale status
```

From another device in the same tailnet, open `http://orangebox-vm:8080/`, or use its Tailscale IPv4 address if MagicDNS is disabled. Tailnet policy must permit TCP 8080. The page lets you name and increment a persistent Durable Object counter. `GET /api/counter/NAME` reads it; `POST /api/counter/NAME` increments it. The original `GET /alice` JSON demo also remains available and increments on every request.

## Manage and restart

```sh
bash scripts/vm.sh status
bash scripts/vm.sh ssh
journalctl --user -u openorange-homelab-vm -f
bash scripts/vm.sh stop  # orderly guest poweroff
bash scripts/vm.sh start # reuse the existing disk and enrollment
```

The transient user service survives closing this chat, but is not enabled to launch automatically after a host reboot. Re-run `start` after reboot. It refuses to launch a second service with the same name. The full OS runs from the built Nix closure; rebuild and restart to apply configuration changes. Deploying a new Worker image only restarts the Worker service. The first boot may log Worker image-pull failures until `deploy-demo` imports the locally built image.
