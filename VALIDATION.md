# Validation — November 12, 2026

Passed on the development machine:

- `nix flake check --print-build-logs`: complete base NixOS evaluation, example-workload wiring/firewall assertions, example OS derivation evaluation, ShellCheck on all setup scripts.
- `nix eval .#nixosConfigurations.minipc.config.system.build.toplevel.drvPath`: complete base OS derivation evaluates.
- Example `npm ci`, `orange deploy --dry-run` and the generated Docker image build on x86-64 Linux.
- Started the pinned Engine with local file-backed object storage, a generated admin token and a 2 GiB / 2 CPU limit. Created the `hello` pool through the authenticated API. Started the generated Worker with host networking, loopback HTTP binding, a state volume, dropped capabilities, no-new-privileges, and a 2 GiB / 2 CPU limit.
- Called `/alice`: durable count 1, then 2. Stopped the Worker, restarted Engine, started Worker: durable count 3. Removed the temporary test containers afterward.

The Engine image shown in the upstream quickstart (`3.0.1`) returned HTTP 500 to OpenOrange 1.0.1's bundled SDK. The configuration therefore pins **Engine 3.1.2-rc.1**, matching the bundled `rivetkit` version, by its Docker registry digest. This is a prerelease dependency; update Engine and OpenOrange together and retest. The generated Worker Dockerfile still uses upstream's mutable `node:24-slim` base. Build once and deploy an immutable image digest for repeatable rollout.

`npm audit` reported **12 dependency advisories (7 moderate, 5 high)** in the example's locked OpenOrange dependency tree, including transitive Wrangler/Miniflare, Undici, Zod and Sharp advisories. No forced upgrades or compatibility-breaking overrides were applied. Inspect `npm audit` when updating; keep this installation restricted to your tailnet and trusted applications.

Not performed: a full NixOS system closure build, a VM boot, installation on the user's mini PC, actual Tailscale enrollment/policy validation, filesystem restore testing or a hardware power-loss test. The installer’s destructive partitioning commands were reviewed and linted, not run against a disk. Hardware, boot mode and networking must be verified during the physical installation. CI evaluates and lints; it does not claim hardware or runtime coverage.
