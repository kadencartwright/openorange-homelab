#!/usr/bin/env bash
# Run from a NixOS graphical/minimal installer booted in UEFI mode.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 ]]; then echo "Usage: sudo $0 /dev/disk/by-id/INSTALL-DISK /path/to/id_ed25519.pub" >&2; exit 2; fi
disk=$(readlink -f "$1")
key=$(realpath "$2")
[[ $EUID == 0 && -d /sys/firmware/efi ]] || { echo 'Root and UEFI boot required.' >&2; exit 1; }
[[ $(uname -m) == x86_64 && -b $disk && -f $key ]] || { echo 'Need x86_64, a block device and a public key file.' >&2; exit 1; }
public_key=$(cat "$key")
[[ $public_key != *$'\n'* && $public_key =~ ^(ssh-|ecdsa-|sk-) ]] || { echo 'Provide a single OpenSSH PUBLIC key, never a private key.' >&2; exit 1; }
ssh-keygen -l -f "$key" >/dev/null
mountpoint -q /mnt && { echo '/mnt is already mounted; unmount it first.' >&2; exit 1; }
[[ $(lsblk -dn -o TYPE "$disk") == disk ]] || { echo 'Select a whole disk.' >&2; exit 1; }
if lsblk -nr -o MOUNTPOINT "$disk" | grep -q '[^[:space:]]'; then
  echo 'Disk has mounted filesystems. Unmount them before installing.' >&2; exit 1
fi
if [[ -n $(swapon --noheadings --raw --show=NAME) ]]; then
  echo 'Disable swap on the installation disk (swapoff) before continuing.' >&2; exit 1
fi
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS "$disk"
printf '\nThis ERASES all partitions on %s. Type ERASE %s: ' "$disk" "$disk"
read -r answer
[[ $answer == "ERASE $disk" ]] || exit 1
parted --script "$disk" mklabel gpt mkpart ESP fat32 1MiB 1025MiB set 1 esp on mkpart root ext4 1025MiB 100%
udevadm settle
part1=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2 == 1 {print $1}')
part2=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2 == 2 {print $1}')
[[ -b $part1 && -b $part2 ]]
mkfs.fat -F 32 -n EFI "$part1"
mkfs.ext4 -F -L nixos "$part2"
mount "$part2" /mnt
mkdir -p /mnt/boot
mount "$part1" /mnt/boot
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/minipc/hardware-configuration.nix
# jq is supplied by `nix develop`; its input is a public key, never a private key.
tmp=$(mktemp)
jq --arg key "$(cat "$key")" '.sshAuthorizedKeys = [$key]' hosts/minipc/settings.json > "$tmp"
cat "$tmp" > hosts/minipc/settings.json
rm "$tmp"
git add hosts/minipc/hardware-configuration.nix hosts/minipc/settings.json
mkdir -p /mnt/etc/nixos/openorange
cp -a . /mnt/etc/nixos/openorange/
nixos-install --no-root-passwd --flake /mnt/etc/nixos/openorange#minipc
echo 'Set a LOCAL CONSOLE password for lab (SSH password login remains disabled):'
nixos-enter --root /mnt -c 'passwd lab'
cat <<'NEXT'
Installed. Reboot, then use the PHYSICAL console:
  sudo tailscale up
Approve the displayed login URL from another device. SSH is tailnet-only:
  ssh lab@orangebox
Your repo is /etc/nixos/openorange. Commit the generated hardware and public key
configuration there before future deploys. No password login is configured.
NEXT
