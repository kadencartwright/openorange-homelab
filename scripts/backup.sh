#!/usr/bin/env bash
# A consistent offline backup; the destination should be on an off-box mount.
set -euo pipefail
[[ $EUID == 0 && $# == 1 ]] || { echo "Usage: sudo $0 /mnt/offbox-backups" >&2; exit 2; }
dest=$(realpath "$1")
[[ -d $dest && $dest != /var/lib/openorange* ]] || exit 2
umask 077
units=()
while IFS= read -r unit; do
  if [[ -n $unit ]] && systemctl is-active --quiet "$unit"; then units+=("$unit"); fi
done < /etc/openorange/units
engine_active=false
systemctl is-active --quiet docker-rivet && engine_active=true
restart() {
  if $engine_active; then systemctl start docker-rivet; fi
  if [[ ${#units[@]} -gt 0 ]]; then systemctl start "${units[@]}"; fi
}
trap restart EXIT
if [[ ${#units[@]} -gt 0 ]]; then systemctl stop "${units[@]}"; fi
if $engine_active; then systemctl stop docker-rivet; fi
archive="$dest/openorange-$(date -u +%Y%m%dT%H%M%S)-$$.tar.gz"
tar --acls --xattrs --numeric-owner -C /var/lib -czf "$archive.partial" openorange
mv "$archive.partial" "$archive"
sha256sum "$archive" > "$archive.sha256"
echo "$archive"
