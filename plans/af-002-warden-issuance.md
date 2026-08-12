# Implement AF-002 Warden issuance and policy evaluation

This ExecPlan is a living document and must be maintained in accordance with `.agent/PLANS.md`.

## Purpose / Big Picture

After this change, callers can submit a normalized Agent issuance request to a provider-neutral Warden authority service and receive one of three outcomes: `ALLOW`, `ESCALATE`, or `DENY`. An `ALLOW` outcome produces a bounded authority envelope and issuance record only when Registry-backed principal, Pack, request, and policy inputs are valid. The OpenAI Agents SDK remains outside the authority boundary; it can consume the resulting issuance later but cannot create or expand it.

The behavior is observable through focused unit tests in `packages/warden-authority/test/issuance.test.ts` and through a small pure TypeScript API exported from `packages/warden-authority/src/index.ts`.

## Progress

- [x] 2026-08-12T20:50:00Z Inspected repository contributor instructions and ExecPlan requirements.
- [x] 2026-08-12T20:52:00Z Selected a new isolated `packages/warden-authority` package so authority logic does not enter `agents-core`.
- [ ] Implement normalized issuance types, policy rules, evaluator, and authority-envelope derivation.
- [ ] Add tests covering allow, escalate, deny, model self-authority rejection, capability attenuation, validity, and deterministic hashes.
- [ ] Run focused package checks and broader repository checks where available.
- [ ] Open a draft PR and record any infrastructure limitations.

## Surprises & Discoveries

- Observation: The repository is the OpenAI Agents JS monorepo and does not currently contain a separate Warden authority package.
  Evidence: `packages/` currently contains only `agents`, `agents-core`, `agents-openai`, `agents-realtime`, and `agents-extensions`.

## Decision Log

- Decision: Add `packages/warden-authority` rather than modifying `agents-core`.
  Rationale: `agents-core` defines agent workflow/runtime abstractions. AF-002 must preserve `Agent runtime != Warden authority`; an isolated package makes that boundary enforceable and provider-neutral.
  Date/Author: 2026-08-12 / OpenAI.

- Decision: Implement the first policy engine as deterministic rule evaluation over normalized inputs, with no model call inside authorization.
  Rationale: Model output must never manufacture authority. AF-002 only needs the first `ALLOW | ESCALATE | DENY` boundary and a bounded envelope that can later be persisted through AF-001.
  Date/Author: 2026-08-12 / OpenAI.

## Outcomes & Retrospective

Implementation is in progress. This section will be updated with verification evidence and remaining integration work before handoff.

## Context and Orientation

`packages/agents-core` contains the provider-neutral agent workflow runtime. It is useful later as a cognition/orchestration substrate, but it is not the Warden authority service. AF-001 in the separate Registry/control-plane repository defines persistence identifiers for Agent profiles, Packs, Agent identities, issuance requests, authority envelopes, issuances, model bindings, effects, and revocations. AF-002 therefore defines a pure authority-domain contract that can consume those identifiers without importing database or model-provider clients.

A Warden policy rule in this package means an explicit deterministic instruction that matches a requested capability and returns one of three dispositions. `ALLOW` means the capability may be included in the bounded envelope, `ESCALATE` means a separate authority decision is required and the capability is not autonomous, and `DENY` means the capability must be excluded. The evaluator never executes tools and never calls an LLM.

## Plan of Work

Create `packages/warden-authority/package.json`, `tsconfig.json`, and `tsconfig.test.json` following the existing workspace package conventions. Add `src/types.ts` for normalized request, policy, decision, envelope, and issuance types. Add `src/evaluate.ts` with deterministic capability evaluation and fail-closed defaults. Add `src/issue.ts` to validate resolved Registry inputs, attenuate requested capabilities into allowed/escalated/denied sets, derive a stable envelope hash, and create a short normalized issuance result only for an `ALLOW` request-level outcome. Export the public API from `src/index.ts`.

Add tests under `packages/warden-authority/test/issuance.test.ts`. Tests must prove that unknown capabilities deny by default, escalation is not silently upgraded, a model/runtime claim cannot add authority, capability sets are attenuated to policy, invalid or expired Registry/Pack inputs deny issuance, and identical inputs produce the same authority-envelope hash.

## Concrete Steps

From the repository root, run:

    pnpm -F @believers-common/warden-authority build-check
    pnpm -F @believers-common/warden-authority test

Then run proportionate repository checks:

    pnpm lint
    pnpm -F @believers-common/warden-authority build

If the full monorepo is practical on the connected runner, also run:

    pnpm -r build-check
    CI=1 pnpm test

Expected focused result: all AF-002 tests pass with no network credentials and no model-provider API calls.

## Validation and Acceptance

Acceptance requires observable tests for at least these cases. A Base Agent request for `entity.profile.read` and `service_request.create` is allowed when explicit policy allows both. `commercial_exception` returns escalation when policy says escalate. `contract.execute`, `payment.approve`, and `authority.delegate` deny. An unknown capability denies. Any attempted model/runtime-supplied authority additions are ignored or rejected because the evaluator derives authority only from the normalized request plus Warden policy. Expired principal, Pack, or policy validity causes fail-closed denial. An `ALLOW` result returns a bounded envelope with separate allowed, escalated, and denied capabilities and a deterministic content hash.

## Idempotence and Recovery

The evaluator is pure and has no side effects. Re-running it with the same normalized input produces the same decision and envelope hash. No live Warden, Registry, model, database, tool, credential, or production system is modified by these tests.

## Artifacts and Notes

The first integration consumer will be the AF-001 Registry persistence boundary. The package deliberately returns normalized identifiers and evidence/authorization references rather than performing persistence itself.

## Interfaces and Dependencies

The package must export an `evaluateIssuanceRequest(input)` function that accepts resolved principal, Pack, requested capability, policy, and validity context and returns a normalized result. It must not depend on `@openai/agents-core`, OpenAI APIs, provider SDKs, Supabase, Neon, Vercel, or production secrets. It may use Node standard-library cryptography to hash the canonical authority envelope.

Revision note: initial ExecPlan created to establish the AF-002 authority boundary before code changes.