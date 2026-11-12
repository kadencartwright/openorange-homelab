#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
state=${OPENORANGE_VM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/openorange-homelab-vm}
unit=openorange-homelab-vm
ssh_vm() {
  ssh -i "$state/management" -p 22222 \
    -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=$state/known_hosts" lab@127.0.0.1 "$@"
}
case ${1:-status} in
  start)
    if systemctl --user is-active --quiet "$unit"; then
      echo 'VM is already running. Use stop before starting a rebuilt configuration.' >&2; exit 1
    fi
    mkdir -p "$state/share"
    chmod 700 "$state"
    if [[ ! -f $state/management ]]; then ssh-keygen -q -t ed25519 -N '' -f "$state/management" -C openorange-vm-management; fi
    cp "$state/management.pub" "$state/share/management.pub"
    cd "$repo"
    nix --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.vm.config.system.build.vm -o result-vm
    runner=$(realpath result-vm/bin/run-orangebox-vm-vm)
    systemd-run --user --collect --unit="$unit" \
      --property="WorkingDirectory=$state" \
      --setenv="OPENORANGE_VM_STATE_DIR=$state" \
      --setenv="NIX_DISK_IMAGE=$state/disk.qcow2" "$runner"
    echo "VM started. Disk and management key: $state"
    echo "Logs: journalctl --user -u $unit -f"
    ;;
  stop)
    ssh_vm sudo poweroff || [[ $? == 255 ]]
    for _ in {1..60}; do
      if ! systemctl --user is-active --quiet "$unit"; then echo 'VM stopped.'; exit 0; fi
      sleep 1
    done
    echo 'VM has not finished shutting down; inspect its journal before restarting.' >&2; exit 1
    ;;
  status) systemctl --user --no-pager status "$unit" ;;
  ssh) shift; ssh_vm "$@" ;;
  deploy-demo)
    bash "$repo/scripts/build-worker.sh" "$repo/examples/hello" localhost/openorange-hello:1
    docker image save localhost/openorange-hello:1 | ssh_vm sudo docker load
    ssh_vm sudo systemctl restart docker-orange-hello
    echo 'Demo deployed. Check with: scripts/vm.sh ssh curl --fail http://127.0.0.1:8080/alice'
    ;;
  *) echo "Usage: $0 {start|stop|status|ssh [command...]|deploy-demo}" >&2; exit 2 ;;
esac
