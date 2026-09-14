# Warden Audit Target Admission Gate

This local-first gate proves that an audit target is the intended, ready service before Lighthouse or another auditor is allowed to run.

From the repository root, start the included target and gate in separate terminals:

    pnpm warden:demo-target
    pnpm warden:audit-gate

Open `http://127.0.0.1:4310`. The demo target is `http://127.0.0.1:4311/` and its expected identity is `alpha-demo`.

Both services bind to `0.0.0.0` by default so Windows can reach a service launched in WSL when WSL localhost forwarding is enabled. The important rule is to enter the URL visible from the auditor environment, not a URL that works only inside the target's environment. If Windows cannot reach WSL through localhost, find the WSL address with `wsl hostname -I`, use `http://<wsl-address>:4311/` in the UI, and allow that port through the applicable local firewall policy. You can override bindings with `WARDEN_GATE_HOST`, `WARDEN_GATE_PORT`, `WARDEN_TARGET_HOST`, and `WARDEN_TARGET_PORT`.

The gate exposes:

- `GET /readyz` for gate readiness.
- `POST /api/admit` with `{ "url": "...", "expectedServiceId": "..." }`.
- `POST /api/verify` with an existing `bindingId` and `config` to detect drift.
- `GET /api/receipts` for admission evidence generated in the current process.

Targets identify both their root response and readiness response with the `X-Warden-Service-Id` header. A successful admission binds the auditor-visible URL, resolved address, identity, and response fingerprint.
