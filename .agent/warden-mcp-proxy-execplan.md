# Implement WARDEN-MCP-PROXY-001 R0.1

This ExecPlan is a living document maintained in accordance with `.agent/PLANS.md`.

## Purpose / Big Picture

Desktop Commander must remain qualification-only and must never receive a request that has not passed Warden checks. This change adds a small package whose public proxy resolves the caller identity, validates and normalizes arguments, authorizes the resolved filesystem target, removes unapproved environment variables, and writes linked admission and execution evidence. The Phase 3 tests demonstrate both the one allowed staging read and the required refusal cases.

## Progress

- [x] (2026-09-02 12:00Z) Located the active Warden monorepo and inspected its contributor, package, identity, decision, and River evidence conventions.
- [x] (2026-09-02 12:05Z) Confirmed that no Desktop Commander admission artifact is present in the available checkout.
- [x] (2026-09-02 12:15Z) Added the isolated proxy package and qualification artifact.
- [x] (2026-09-02 12:20Z) Ran the focused Phase 3 suite, package type check, targeted lint, and diff check.
- [x] (2026-09-02 12:25Z) Inspected the final diff and recorded exact evidence and gaps.
- [x] (2026-09-02 12:40Z) Added and verified a qualification-only deployment registration invariant that closes the direct transport exposure gap.

## Surprises & Discoveries

- Observation: The referenced `ALPHA-DESKTOP-COMMANDER-ADMISSION-001 R0.1` artifact is not present in any searched Codex workspace checkout.
  Evidence: A content search for its identifier and `DESKTOP-COMMANDER-MCP-001` returned no files.
- Observation: Windows rejected an unprivileged file symlink fixture before the proxy ran.
  Evidence: The first focused test run reported 9 passed and P3.4 failed with `EPERM`; changing the fixture to a directory junction exercised the same real-target escape and all 10 tests passed.

## Decision Log

- Decision: Add `packages/warden-mcp-proxy` rather than modifying the existing Warden primitives.
  Rationale: The working tree already contains user-owned changes, and an additive package gives the new enforcement boundary one owner and avoids changing unrelated APIs.
  Date/Author: 2026-09-02 / Codex.
- Decision: Represent the proxy-only caller restriction with an unexported capability value held by a guarded adapter.
  Rationale: A caller-controlled string or decision-shaped object would be forgeable; an inaccessible object identity demonstrates that the target cannot be called through the package's public API without passing the proxy.
  Date/Author: 2026-09-02 / Codex.
- Decision: Make deployment topology a validated data contract rather than starting a live transport.
  Rationale: Registration invariants are testable without installing or enabling the unqualified Desktop Commander service, which would exceed `QUALIFICATION_ONLY`.
  Date/Author: 2026-09-02 / Codex.

## Outcomes & Retrospective

The four child blocks, mandatory proxy-only target adapter, deny-by-default policy, resolved-target boundary checks, environment sanitization, linked evidence, and deployment registration invariant are implemented. All ten Phase 3 tests and four topology tests pass, and the package passes type checking and targeted linting. Desktop Commander remains `QUALIFICATION_ONLY`. Applying the manifest to a concrete service manager and the referenced but absent admission artifact remain external gaps.

## Context and Orientation

`packages/warden-core` defines allow and deny decisions. `packages/warden-identity` separates authenticated identity from authority. `packages/warden-river` defines evidence concepts. The new `packages/warden-mcp-proxy` package is an executable qualification seam around an injected Desktop Commander executor; it does not install or start Desktop Commander and cannot promote its admission status.

The four requested child blocks are exported classes named `WardenMcpProxyIdentity`, `WardenMcpRequestNormalizer`, `WardenMcpBoundaryEnforcer`, and `WardenMcpEvidenceBridge`. `WardenMcpProxy` composes them in that order and invokes the target only after an allow decision has been recorded.

## Plan of Work

Create package metadata and TypeScript configuration following adjacent Warden packages. Implement strict request parsing, an explicit identity allowlist, canonical and real path resolution, resolved-target boundary checks, blocked filename rules, environment allowlisting with a synthetic HOME below the staging root, an unforgeable proxy-call capability, and linked in-memory admission/execution evidence. Add a qualification document that fixes admission at `QUALIFICATION_ONLY` and records the absent source artifact as a gap. Add ten Phase 3 tests using temporary real directories, including a real filesystem symlink when the host permits it.

## Concrete Steps

From the Warden repository root, run `pnpm exec vitest run packages/warden-mcp-proxy/test/phase3.test.ts` and expect ten passing tests. Then run `pnpm -F @warden/mcp-proxy build-check` and expect exit status zero. Inspect `git diff -- packages/warden-mcp-proxy docs/WARDEN-MCP-PROXY-001.md tsc-multi.json` before reporting.

## Validation and Acceptance

P3.1 must prove an allowed read reaches the injected executor and emits linked allow and success events. P3.2 through P3.10 must prove direct bypass is rejected, traversal and symlink escapes are denied, blocked filenames are denied, secret environment keys are stripped while HOME is synthetic, malformed arguments are denied, execution evidence cannot be created without an allow decision, unknown callers are denied, and unknown tools are denied by default. Every denial must leave the target invocation count unchanged. The package type check must pass.

## Idempotence and Recovery

Tests use independently created temporary directories and remove only those exact directories. All source changes are additive except the new entry in `tsc-multi.json`; rerunning tests is safe.

## Artifacts and Notes

The initial test run produced 9 passes and one Windows fixture error (`EPERM` creating a file symlink). The corrected Phase 3 run produced `Test Files 1 passed` and `Tests 10 passed`. After the topology addition, the combined run produced `Test Files 2 passed` and `Tests 14 passed`. `pnpm -F @warden/mcp-proxy build-check` and targeted ESLint each exited zero.

## Interfaces and Dependencies

The implementation uses only Node built-ins and Vitest already present in the workspace. The target executor has an `execute(request)` method. The proxy exposes `invoke(unknown)` and returns an allow result with output or a deny result with a stable reason code and request fingerprint. The evidence bridge exposes immutable snapshots for qualification inspection.

Revision note: Updated after implementation and verification to record the Windows fixture discovery, deployment topology contract, final evidence, and remaining service-manager/provenance gaps.
