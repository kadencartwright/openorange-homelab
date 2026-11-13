#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 && $# == 1 ]] || { echo "Usage: sudo $0 /mnt/offbox-backups" >&2; exit 2; }
dest=$(realpath "$1")
[[ -d $dest && $dest != /var/lib/folio* ]] || exit 2
umask 077
units=()
for unit in docker-folio-engine docker-folio folio-migrations; do
  if systemctl is-active --quiet "$unit"; then units+=("$unit"); fi
done
restart() { if [[ ${#units[@]} -gt 0 ]]; then systemctl start "${units[@]}"; fi; }
trap restart EXIT
systemctl stop folio-migrations docker-folio docker-folio-engine
archive="$dest/folio-$(date -u +%Y%m%dT%H%M%S)-$$.tar.gz"
tar --acls --xattrs --numeric-owner -C /var/lib -czf "$archive.partial" folio
mv "$archive.partial" "$archive"
sha256sum "$archive" > "$archive.sha256"
echo "$archive"
