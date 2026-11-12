#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $EUID == 0 ]] || { echo "Usage: sudo $0 [boot|switch|test]" >&2; exit 2; }
action=${1:-switch}
[[ $action =~ ^(boot|switch|test)$ ]] || exit 2
[[ $(jq '.sshAuthorizedKeys | length' hosts/minipc/settings.json) -gt 0 ]] || { echo 'Configure an SSH public key first.' >&2; exit 1; }
exec nixos-rebuild "$action" --flake .#minipc
