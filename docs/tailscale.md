# Tailnet access

Enroll at the physical console using `sudo tailscale up`. Review the device in the Tailscale admin console, enable MagicDNS if desired, and decide how to handle device key expiry for an unattended server. This repo does not change your account policy, enable Tailscale SSH, advertise subnet routes or configure an exit node.

Use the normal OpenSSH server with your SSH public key. The OS firewall permits SSH and configured Worker proxy ports only on `tailscale0`. LAN SSH is deliberately closed; keep physical console access available during enrollment or network changes.

For a restricted tailnet, merge a grant like this into your existing policy, replacing both addresses (do not overwrite your whole policy):

```json
{
  "grants": [
    {
      "src": ["your-login@example.com"],
      "dst": ["100.101.102.103"],
      "ip": ["tcp:22", "tcp:8080"]
    }
  ]
}
```

`dst` is the mini PC's Tailscale IP (`tailscale ip -4`), not its LAN IP. Add only the application ports you configure. Existing broad grants/ACLs still apply, so inspect the complete policy if you want restrictions. See [Tailscale grants](https://tailscale.com/kb/1324/grants).
