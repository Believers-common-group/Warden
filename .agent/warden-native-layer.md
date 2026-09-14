# Add the first Warden-native packages

This ExecPlan is a living document maintained according to `.agent/PLANS.md`.

## Purpose / Big Picture

After this change, Warden consumers can model DigitalMe identity, Warden authorization decisions, and River-compatible execution receipts without changing or depending on the internal implementation of the upstream OpenAI Agents SDK. The behavior is demonstrated by focused unit tests that keep authentication separate from authority, make denied actions non-executable, and preserve the difference between the actor requesting an effect and the executor carrying it out.

## Progress

- [x] (2026-08-20 00:00Z) Located a clean checkout and inspected workspace, TypeScript, package, and test conventions.
- [x] (2026-08-20 00:10Z) Created `feat/warden-native-foundations` and three package skeletons.
- [x] (2026-08-20 00:15Z) Added minimal public types and invariant-preserving decision helpers.
- [x] (2026-08-20 00:18Z) Added focused unit tests and minimal architecture documentation.
- [x] (2026-08-20 00:35Z) Installed with repository-pinned pnpm 10.26.1 and ran focused tests and type checks.
- [x] (2026-08-20 00:45Z) Ran lint, dual-format build, all workspace build checks, and all tests successfully.
- [x] (2026-08-20 00:55Z) Reviewed the final diff, removed tool-generated lockfile noise, and verified the minimal lockfile with frozen installation.

## Surprises & Discoveries

- Observation: The repository remains configured as the upstream `openai-agents-js` workspace and `tsc-multi.json` enumerates packages explicitly.
  Evidence: The root package name is `openai-agents-js`, and the build project list contains only the five existing `@openai` packages.
- Observation: Vitest's root global setup loads upstream source that expects the generated `@openai/agents-core/_shims` export, so tests require the normal prebuild/build step in a fresh checkout.
  Evidence: The first focused Vitest run stopped in `packages/agents-core/src/tracing/context.ts` before collecting Warden tests because the shim package export did not yet exist.
- Observation: A dependent package's test config must map workspace dependencies to source, matching existing package test conventions.
  Evidence: River's first `build-check` could not resolve `@warden/core`; adding a test-only `paths` mapping provides source-level type checking.

## Decision Log

- Decision: Add independently published-style packages named `@warden/identity`, `@warden/core`, and `@warden/river` under `packages/`.
  Rationale: This makes the Warden boundary explicit while allowing pnpm workspace discovery and avoiding edits to upstream SDK source packages.
  Date/Author: 2026-08-20 / Codex.
- Decision: Use discriminated unions for decisions, with an `actionContract` present only on the allowed variant.
  Rationale: TypeScript then prevents denied decisions from carrying executable contracts, while a small runtime constructor provides directly testable behavior.
  Date/Author: 2026-08-20 / Codex.

## Outcomes & Retrospective

The three additive Warden packages now compile in the monorepo's CommonJS and ES module build, expose the requested minimal public types, and preserve each requested invariant through four focused tests. No existing OpenAI Agents SDK source or package interface was modified. The only upstream-level integration edits are the root README, the explicit `tsc-multi.json` project list, and three importer records in `pnpm-lock.yaml`.

Fresh validation passed: focused Warden Vitest ran 4 tests in 3 files; focused package build checks passed; ESLint passed; `pnpm build` reported zero errors for both output formats; all 28 package/example build checks passed; and the full Vitest suite passed 726 tests in 76 files. On Windows, the repository's Unix-form `pnpm test` script could not parse `CI=1`; its equivalent environment was applied directly to `vitest run`. A frozen pnpm 10.26.1 install accepted the final lockfile.

## Context and Orientation

The repository is a pnpm TypeScript monorepo. `pnpm-workspace.yaml` discovers every directory under `packages/`, while `tsc-multi.json` explicitly lists packages built in both CommonJS and ES module formats. Existing SDK internals live in `packages/agents-*`; this work adds sibling packages only. Vitest discovers tests under every package through root `vitest.config.ts`.

A provider identity is an account asserted by an authentication provider such as GitHub. A DigitalMe principal is Warden's canonical identity. A binding records their association but does not grant authority. An Action Contract is an approved, immutable description of an intended effect. A receipt records the effect and evidence after execution, including distinct actor and executor identities.

## Plan of Work

Create the three sibling package directories with standard `package.json`, `tsconfig.json`, `tsconfig.test.json`, public `src/index.ts`, and focused tests. Add each package to `tsc-multi.json`. Keep identity types free of authority fields. Model core decisions as a discriminated union and expose constructors that cannot create an executable contract for a denial. Model River receipts with separate required `actor` and `executor` fields and effect evidence. Add a short root README section describing the additive boundary and compatibility posture.

## Concrete Steps

From the repository root, create branch `feat/warden-native-foundations`. Add files using repository formatting. Run `pnpm install` so the workspace lockfile records the new local dependency, then focused tests and build checks for the three packages. Finally run the mandated sequence `pnpm lint`, `pnpm build`, `pnpm -r build-check`, and `pnpm test` in that order.

## Validation and Acceptance

Focused Vitest cases must show that a GitHub identity contains authentication facts but no Warden authority, that resolving a principal returns a distinct DigitalMe object, that a denied decision has no Action Contract, and that a receipt retains different actor and executor values. Type checking must also validate all public declarations. The repository-wide commands must exit successfully, or any unrelated/environmental failure must be classified with evidence.

## Idempotence and Recovery

All source edits are additive except the explicit build-project list and README section. Commands are safe to rerun. Generated `dist` output is ignored by Git. No commit, push, publication, or pull request is part of this plan.

## Artifacts and Notes

The final tracked integration diff contains ten README lines, ten lockfile importer lines, and the three additions to `tsc-multi.json`, plus the new plan and package directories. All relevant commands exited zero except the documented Unix-script invocation on Windows, which failed before test collection and was replaced by its exact platform-equivalent invocation.

## Interfaces and Dependencies

`@warden/identity` exports a string ID alias, `DigitalMePrincipal`, generic `ProviderIdentity`, `IdentityProvider`, `GitHubIdentity`, `GitHubProviderBinding`, `IdentityBinding`, and `WardenSessionIdentity`. `@warden/core` exports authority and consent records, `ActionContract`, allowed and denied decision variants, and decision constructors. `@warden/river` exports receipt parties, effect evidence, and an execution receipt. Dependencies between these packages are permitted only through their public workspace package names; none may import from `packages/agents-*` internals.

Plan update note: Updated after the first implementation slice to record the branch, package APIs, tests, documentation, and the need to refresh the lockfile for the new workspace dependency.

Plan update note: Updated during focused verification to record the fresh-checkout upstream shim prerequisite and River's test-only source mapping.

Plan update note: Finalized after full verification and diff cleanup with outcomes, command evidence, the Windows test-script limitation, and frozen-lockfile acceptance.
