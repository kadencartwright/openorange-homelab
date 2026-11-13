#!/usr/bin/env bash
# Run as the Ubuntu account that will own the VM. Uses sudo for the unit only.
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run as the VM owner, using passwordless sudo.' >&2; exit 2; }
repo=$(cd "$(dirname "$0")/.." && pwd)
state=${OPENORANGE_VM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/openorange-homelab-vm}
user=$(id -un)
[[ -c /dev/kvm ]] || { echo 'KVM is unavailable.' >&2; exit 1; }
[[ $repo != *' '* && $state != *' '* ]] || { echo 'Use paths without spaces for the service.' >&2; exit 2; }
sudo -n true
if sudo systemctl is-active --quiet openorange-homelab-vm; then echo 'Stop the existing system VM service before updating it.' >&2; exit 1; fi
mkdir -p "$state/share"
chmod 700 "$state"
if [[ ! -f $state/management ]]; then ssh-keygen -q -t ed25519 -N '' -f "$state/management" -C openorange-vm-management; fi
cp "$state/management.pub" "$state/share/management.pub"
[[ ! -f $state/MIGRATED_TO ]] || { echo 'This state was migrated to another host. Refusing to duplicate its identity.' >&2; exit 1; }
nix_bin=${NIX_BIN:-/nix/var/nix/profiles/default/bin/nix}
cd "$repo"
"$nix_bin" --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.vm.config.system.build.vm -o result-vm
# Keep result-vm as a GC root; use its stable path for subsequent rebuilds.
sudo install -m 0644 /dev/stdin /etc/systemd/system/openorange-homelab-vm.service <<UNIT
[Unit]
Description=OpenOrange NixOS home lab VM
Wants=network-online.target
After=network-online.target nix-daemon.service
Requires=nix-daemon.service
ConditionPathExists=!$state/MIGRATED_TO

[Service]
Type=simple
User=$user
SupplementaryGroups=kvm
WorkingDirectory=$state
Environment=OPENORANGE_VM_STATE_DIR=$state
Environment=NIX_DISK_IMAGE=$state/disk.qcow2
ExecStart=$repo/result-vm/bin/run-orangebox-vm-vm
ExecStop=/bin/bash $repo/scripts/vm-service-stop.sh $state
TimeoutStopSec=120
KillMode=mixed
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable openorange-homelab-vm
echo 'Installed boot-persistent service. Start with: sudo systemctl start openorange-homelab-vm'
