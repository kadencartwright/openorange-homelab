#!/usr/bin/env bash
set -euo pipefail
systemctl --no-pager --full status tailscaled docker-rivet openorange-pools
curl --fail --silent --show-error http://127.0.0.1:6420/health
printf '\n'
tailscale status
while IFS= read -r unit; do
  [[ -z $unit ]] || systemctl --no-pager --full status "$unit"
done < /etc/openorange/units
