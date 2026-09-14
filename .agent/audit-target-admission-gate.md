# Build a local Audit Target Admission Gate

This ExecPlan is a living document maintained according to `.agent/PLANS.md`.

## Purpose / Big Picture

After this change, an operator can open a local Warden page, enter the URL and expected identity of an audit target, and see the target advance through discovery, resolution, reachability, HTTP response, identity, readiness, and admission checks. An admitted result is bound to the observed service instance and produces an evidence receipt; a later change is blocked instead of silently auditing a different target.

## Progress

- [x] (2026-08-27 18:40Z) Inspected the Alpha/Warden monorepo, repository instructions, current branch, and user-owned changes.
- [x] (2026-08-27 18:45Z) Selected an additive `@warden/audit-gate` package using the existing TypeScript and Vitest stack.
- [x] (2026-08-27 18:15Z) Implemented the admission state machine, local HTTP service, demo target, UI, and receipts.
- [x] (2026-08-27 18:16Z) Added eight focused tests for admission, required block reasons, and post-admission target changes.
- [x] (2026-08-27 18:20Z) Verified both readiness endpoints and a seven-state admission from the Windows auditor on stable ports.
- [x] (2026-08-27 18:25Z) Ran focused compilation/lint and the full test suite; classified one unrelated upstream build dependency failure.

## Surprises & Discoveries

- Observation: The current Warden work is an uncommitted additive layer inside the OpenAI Agents JS monorepo.
  Evidence: `git status` lists the Warden packages as added files on `feat/warden-native-foundations`.
- Observation: The Codex pnpm wrapper upgraded the workspace link layout and its ignored-build policy prevents normal wrapper commands from completing, although direct repository binaries work.
  Evidence: direct TypeScript, ESLint, and Vitest commands run; pnpm reports `ERR_PNPM_IGNORED_BUILDS` for pre-existing Prisma, esbuild, Sharp, and Tailwind packages.
- Observation: The repository-wide dual-format build has an unrelated missing `undici-types` declaration in `packages/agents-extensions` after the dependency relink.
  Evidence: `tsc-multi` reports TS2307 in `packages/agents-extensions/src/TwilioRealtimeTransport.ts`; the new audit-gate focused build passes.

## Decision Log

- Decision: Add one dependency-free Node package named `@warden/audit-gate` and use ports 4310 for the gate and 4311 for the included demo target.
  Rationale: The existing stack is TypeScript and Node. Fixed, uncommon ports make the auditor boundary repeatable while environment variables still allow a deliberate override.
  Date/Author: 2026-08-27 / Codex.
- Decision: Treat the target URL as the auditor-visible Door and require an explicit expected service identity.
  Rationale: A port is transient routing data; admission must prove the service behind it is the intended application.
  Date/Author: 2026-08-27 / Codex.

## Outcomes & Retrospective

The LG Gram now runs a local Warden admission gate on port 4310 and a deterministic Alpha target on 4311. The gate exposes a visual seven-state pipeline, all required block reasons, readiness and admission APIs, instance bindings, drift verification, and in-memory evidence receipts. Focused compilation, lint, and eight tests pass; the full repository suite passes 734 tests in 77 files. A real request from the Windows auditor admitted the target and produced binding `54b3751d-aa02-4faf-87a5-a3c165b56498` and receipt `a645640b-53d6-4ac6-926c-b0822adc7cfd`. The only broad-check gap is the unrelated upstream `undici-types` declaration failure described above.

## Context and Orientation

The repository is a pnpm TypeScript monorepo. `packages/warden-core` contains authorization primitives and `packages/warden-river` contains receipt primitives. The new `packages/warden-audit-gate` package is an executable local service and reusable admission library. A target is the web application Lighthouse will inspect. The auditor is the Windows process running this gate. A binding is a snapshot of target URL, identity, readiness response, and content fingerprint made at admission time.

## Plan of Work

Create a typed state machine that validates configuration, resolves the host, opens a TCP connection from the auditor process, fetches the root HTTP response, rejects browser interstitials, verifies the declared service identity, calls `/readyz`, and emits either an admission binding or a named block reason. Add a second check that compares the current observation with the binding. Wrap it in a local JSON API, serve a simple static UI, and include a deterministic demo target. Keep receipts in memory for this first local version and expose them through the API.

## Concrete Steps

From the repository root, add `packages/warden-audit-gate`, register it in `tsc-multi.json`, and add root scripts for starting the gate and demo target. Run focused Vitest and TypeScript checks, then the repository validation sequence. Start both services on Windows and call the gate `/readyz`, target `/readyz`, and admission API from this same auditor environment.

## Validation and Acceptance

The UI at `http://127.0.0.1:4310` must display the seven ordered states and all required block reason names. `GET /readyz` must return HTTP 200. Admitting the demo target at `http://127.0.0.1:4311` with identity `alpha-demo` must return `ADMITTED`, seven passed states, a binding, and a receipt. Tests must independently exercise configuration, listening, reachability, wrong identity, interstitial, readiness, and changed-target failures.

## Idempotence and Recovery

All source changes are additive and commands are safe to rerun. The services bind only to explicit local addresses. If a port is occupied, the process exits with a clear error; the operator can stop the conflicting process or deliberately override `WARDEN_GATE_PORT`, `WARDEN_TARGET_PORT`, or `WARDEN_GATE_HOST`.

## Artifacts and Notes

Windows `Test-NetConnection` reported `TcpTestSucceeded: True` for ports 4310 and 4311. Both `/readyz` calls returned HTTP 200. The admission response contained the ordered states `DISCOVERED`, `RESOLVED`, `REACHABLE`, `RESPONDING`, `IDENTITY_VERIFIED`, `READY`, and `ADMITTED`, all passed.

## Interfaces and Dependencies

`admitTarget(config, dependencies?)` returns an `AdmissionResult`. `verifyAdmission(binding, config, dependencies?)` detects target drift. `createGateServer()` exposes `/readyz`, `/api/admit`, `/api/verify`, `/api/receipts`, and the UI. The implementation uses only Node built-ins and the repository's existing TypeScript/Vitest tools.

Plan update note: Created after repository inspection to record scope, ports, package boundary, and acceptance evidence before implementation.

Plan update note: Finalized after implementation and live Windows verification with command evidence, test totals, and the unrelated upstream build limitation.
