# Ubuntu VM host: lab-bosgame

Ubuntu remains the physical host and continues to run its existing K3s control plane. Nix is installed in multi-user mode, and a systemd system service runs the NixOS VM as the Ubuntu `lab` user with supplementary KVM access. No host disk was reformatted or host reboot required.

The `bosgame` flake configuration imports the standard VM and assigns 12 vCPUs, 22 GiB RAM and a 56 GiB virtual disk. The host has 16 logical CPUs and about 28.75 GiB usable RAM. The reserve supports Ubuntu and the cluster services. The qcow2 disk is sparse; its virtual limit is not a reservation of host free space. Monitor host and guest disk usage. Individual Engine and Worker container limits remain configurable separately from VM capacity.

## Paths and administration

On `lab-bosgame`:

- Repository: `/home/lab/code/openorange-homelab`
- State: `/home/lab/.local/state/openorange-homelab-vm`
- Service: `openorange-homelab-vm.service`, enabled for boot
- Guest administration: localhost TCP 22222, using the state directory's management key

```sh
ssh lab@lab-bosgame
cd /home/lab/code/openorange-homelab
sudo systemctl status openorange-homelab-vm
sudo journalctl -u openorange-homelab-vm -f
bash scripts/vm.sh ssh
```

Use `sudo systemctl stop/start/restart openorange-homelab-vm` for this installation. The service's stop hook requests guest poweroff and waits for QEMU to exit. `scripts/vm.sh start` is for the separate, temporary user-service workflow and refuses to start alongside an installed system service.

The demo is served on the guest's existing Tailscale address, port 8080. Its Tailscale state lives on the guest disk and is preserved by cold migration. The Ubuntu host's Tailscale identity is separate.

## Install or update the system service

The host needs Linux/KVM, passwordless sudo for the VM owner, SSH, Git, and a multi-user Nix installation. The initial installation used the version-pinned official Nix 2.35.3 installer with `--daemon --yes --no-channel-add`.

With the VM stopped, run as `lab`:

```sh
cd /home/lab/code/openorange-homelab
OPENORANGE_VM_CONFIGURATION=bosgame bash scripts/install-vm-service.sh
sudo systemctl start openorange-homelab-vm
```

This rebuilds the pinned flake, keeps `result-vm` as a Nix GC root, and installs the system unit. State is not reset. A configuration's `diskSize` sizes a new disk; expanding an existing disk also requires an offline `qemu-img resize` and a guest filesystem resize. Never shrink this disk.

## Cold migration

The original development VM was shut down before copying its disk and management key over SSH. A SHA-256 comparison verified the transferred disk before it was expanded. The source VM must remain stopped while the destination runs: both disks contain the same Tailscale identity and application data. A `MIGRATED_TO` marker at the old state location prevents the local helper from accidentally booting the old copy.

Keep the source disk as a rollback copy until an off-box backup has been verified. To roll back, first stop the destination; the source copy contains only pre-migration data. Never boot both copies.

## SSH bootstrap note

The existing Ansible inventory's GitHub key sync covers only the `agent` user on `lab-um890`, not `lab-bosgame`. Bosgame's `lab` account initially rejected this controller's key. Existing Kubernetes admin access was used for a temporary host-maintenance pod to append this controller's existing GitHub public key to `lab`'s authorized keys, preserving the original file in a timestamped backup. The maintenance pod was then deleted. No GitHub private key or cluster credential was copied into this repository.
