#!/usr/bin/env bash
# systemd supplies MAINPID. Wait for QEMU to exit after guest poweroff.
set -euo pipefail
state=$1
ssh -i "$state/management" -p 22222 -o IdentitiesOnly=yes -o BatchMode=yes \
  -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
  -o "UserKnownHostsFile=$state/known_hosts" lab@127.0.0.1 sudo poweroff || true
for _ in {1..90}; do
  if ! kill -0 "${MAINPID:?systemd MAINPID required}" 2>/dev/null; then exit 0; fi
  sleep 1
done
echo 'Guest did not power off within 90 seconds.' >&2
exit 1
