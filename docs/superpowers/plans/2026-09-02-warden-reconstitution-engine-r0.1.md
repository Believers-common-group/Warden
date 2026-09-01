# Warden Reconstitution Engine R0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps are tracked only in the `Progress` section, in accordance with `.agent/PLANS.md`.

**Goal:** Build `@vsr/warden-reconstitution` as a deterministic, non-mutating TypeScript simulation kernel that evaluates nine organisational transition operations, preserves DigitalMe and historical lineage, computes authority and memory changes, fails closed on governance conflicts, and emits an independently verifiable River-ready simulation receipt without creating live authority or Registry effects.

**Architecture:** The package is an isolated pure kernel under `packages/warden-reconstitution`. External callers supply an immutable `OrganisationSnapshot` and `ProposedTransitionSet`; the kernel validates, canonicalizes, resolves exact references, normalizes successor intents, detects conflicts, derives relationship/assignment lineage, computes authority diffs and memory dispositions, evaluates locked invariants, canonicalizes the semantic result, derives stable SHA-256 hashes and a deterministic simulation ID, and returns a receipt. No database, HTTP, filesystem mutation, agent, LLM, Registry client, River client, device provisioner, network provisioner, or event broker is permitted inside R0.1.

**Tech Stack:** Node.js 22+, TypeScript 5.9.x, pnpm 10.26.x, Zod for runtime input validation, Node `crypto` for SHA-256, Vitest 3.2.x for tests, existing repository ESLint/Prettier/tsc-multi tooling.

**Spec:** `docs/superpowers/specs/2026-09-02-warden-reconstitution-engine-r0.1-design.md`

**Schema Amendment:** `docs/superpowers/specs/2026-09-02-warden-reconstitution-engine-r0.1-schema-amendment.md`. The amendment controls where it conflicts with the original spec.

## Global Constraints

The integration base is `genesis`; implementation occurs on `genesis-warden-reconstitution-r0.1`. The package name is `@vsr/warden-reconstitution`, version `0.1.0`, and it remains `private: true` in R0.1. DigitalMe is the stable principal and cannot be rewritten by role transitions. Historical institutional relationships are append-only historical facts and cannot be edited into successor relationships. Role titles and qualifications never manufacture authority. `MERGE` never unions predecessor permissions implicitly. Cross-institution `TRANSFER` creates a proposed new relationship instead of mutating the old one. `CREATE` requires an explicit target principal and authority basis. `SPLIT` requires one predecessor and at least two independently resolved successor targets. Simulation outputs never create live authority or mutate Registry state. Every receipt must contain the literal booleans `activeAuthorityCreated: false` and `registryMutationPerformed: false`. The kernel performs no database, network, HTTP, filesystem write, LLM, embedding, fuzzy-match, or agent operation. Same semantic input must produce the same semantic result, `simulationId`, and `outputHash`. Receipt emission metadata such as `generatedAt` is excluded from semantic hashing. Ordinary governance denials are structured findings; exceptions are reserved for malformed typed API use or impossible internal/programmer faults. Repository validation must finish with `pnpm lint && pnpm build && pnpm -r build-check && pnpm test`.

---

This ExecPlan is a living document and must be maintained in accordance with `.agent/PLANS.md`. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be updated during implementation so a future worker can resume from this file alone.

## Purpose / Big Picture

After this change, a caller can supply a frozen representation of an organisation and a proposed reorganisation and receive a deterministic answer without changing the organisation. A promotion, transfer, merger, split, suspension, closure, creation, remap, or keep proposal will produce explicit predecessor/successor lineage, authority changes, memory handling, blockers and warnings. The result can be replayed and independently verified by hash.

The primary observable demonstration is a fictional `ORG-ALPHA` fixture. Running the scenario suite must show all nine operations represented, while negative scenarios prove that identity rewrite, historical mutation, implicit authority union, missing authority provenance, unresolved references and incompatible transition proposals fail closed. Running the same semantic input in different array/property orders must yield the same `simulationId` and `outputHash`.

## Progress

- [x] (2026-09-01 22:39Z) Approved architectural design written and committed.
- [x] (2026-09-01 22:39Z) Approved schema amendment written for explicit target principals, multi-successor SPLIT representation, and exact target reference catalogues.
- [ ] Create package scaffold, corrected contracts, Zod validators, and build-system registration.
- [ ] Implement canonicalization, snapshot/transition hashing, deterministic simulation ID, and semantic output hashing.
- [ ] Implement exact reference resolution and normalized successor intents for all nine operations.
- [ ] Implement relationship/assignment lineage projections and operation semantics.
- [ ] Implement semantic authority diffing, risk signalling, memory disposition, conflict detection, and invariant gates.
- [ ] Implement simulation orchestration and River-ready receipt generation/verification.
- [ ] Add ORG-ALPHA fixtures, nine positive scenario tests, required negative tests, determinism/immutability tests, and no-side-effect architecture tests.
- [ ] Run package and whole-repository validation, update plan evidence, and complete retrospective.

## Surprises & Discoveries

- Observation: the repository already has a branch named `genesis`, so Git cannot also create a hierarchical branch `genesis/<workstream>` because refs cannot be both a file and directory.
  Evidence: branch creation for `genesis/warden-reconstitution-r0.1` returned HTTP 422; `genesis-warden-reconstitution-r0.1` was created successfully from `genesis`.

- Observation: implementation planning exposed that the original proposal shape could not represent a predecessor-less `CREATE`, a multi-successor `SPLIT`, or exact local resolution of target roles/institutions/locations.
  Evidence: the approved amendment adds `targetPrincipalRef`, `ProposedSuccessorTarget[]`, and `institutions`/`roles`/`locations` catalogues to the snapshot.

## Decision Log

- Decision: R0.1 is simulation-only and performs no persistent or external effect.
  Rationale: it permits deterministic verification of governance semantics before any execution path exists.
  Date/Author: 2026-09-02 / user-approved design.

- Decision: keep the subsystem in `Believers-common-group/Warden` but isolate it from inherited Agents SDK packages under `packages/warden-reconstitution`.
  Rationale: Warden owns policy/authority simulation, while isolation avoids contaminating `agents-core` with VSR-specific domain semantics.
  Date/Author: 2026-09-02 / user-approved design.

- Decision: use Zod only at the external contract-validation boundary; keep domain algorithms plain TypeScript.
  Rationale: untrusted JSON needs precise runtime validation, while the deterministic kernel should minimize dependencies.
  Date/Author: 2026-09-02 / user-approved design.

- Decision: canonical hashes use SHA-256 over `WARDEN-CANONICAL-JSON-R0.1`; the snapshot hash omits its own `sourceHash`, and the semantic output hash omits receipt metadata and its own hash field.
  Rationale: self-referential fields cannot be hashed recursively, and replay must not depend on clock time.
  Date/Author: 2026-09-02 / implementation-plan clarification consistent with approved hashing contract.

- Decision: `SimulationOptions.receiptGeneratedAt` is optional. If omitted, the deterministic default is `transitionSet.effectiveAt`; callers may supply an ISO-8601 emission timestamp when they need observational receipt time. It never enters `simulationId` or `outputHash`.
  Rationale: this keeps the kernel pure—no direct clock read—while allowing real callers to attach accurate emission metadata.
  Date/Author: 2026-09-02 / implementation-plan clarification consistent with the approved non-semantic `generatedAt` rule.

## Outcomes & Retrospective

No code has been implemented yet. The implementation target is complete when all acceptance gates A01–A20 in the design spec pass, the corrected schema cases pass, and the whole repository validation sequence passes. During implementation this section must record actual outcomes, any deliberate deviations, and remaining R0.2 work.

## Context and Orientation

`Believers-common-group/Warden` is a pnpm TypeScript monorepo forked from OpenAI Agents JS. Its root `pnpm-workspace.yaml` already includes `packages/*`, so a new directory under `packages/` is discovered automatically. Root `vitest.config.ts` also treats `packages/*` as test projects. Root `tsc-multi.json`, however, enumerates package TypeScript projects explicitly, so implementation must append `packages/warden-reconstitution/tsconfig.json` there. The repository contributor guide requires the final validation order `pnpm lint && pnpm build && pnpm -r build-check && pnpm test`.

The term **principal** means the stable DigitalMe identity associated with an assignment. A **relationship** is the effective-dated institutional relationship between a principal and an institution. An **assignment** is a bounded responsibility inside that relationship. An **authority tuple** is one normalized permission statement containing an action, object, scope, purpose, jurisdiction, time/conditions, and authority source. A **successor intent** is an internal normalized description of what a proposal would create or preserve if it were eventually authorized; it has no live effect. **Lineage** is the predecessor/successor link that allows historical reconstruction. A **finding** is a stable warning or blocker code plus context. **Canonicalization** means converting semantically equivalent input into one deterministic JSON representation before hashing.

The corrected R0.1 snapshot must contain principals and exact local reference catalogues:

    export type PrincipalRef = {
      digitalMeId: string;
    };

    export type InstitutionSnapshotRef = {
      institutionId: string;
      name?: string;
    };

    export type RoleSnapshotRef = {
      roleId: string;
      name?: string;
    };

    export type LocationSnapshotRef = {
      locationId: string;
      institutionId: string;
      name?: string;
    };

    export type RelationshipSnapshot = {
      relationshipId: string;
      digitalMeId: string;
      institutionId: string;
      status: 'ACTIVE' | 'SUPERSEDED' | 'CLOSED';
      effectiveFrom: string;
      effectiveTo?: string;
    };

    export type AssignmentSnapshot = {
      assignmentId: string;
      relationshipId: string;
      digitalMeId: string;
      roleId: string;
      institutionId: string;
      locationId?: string;
      authorityRefs: string[];
      status: 'ACTIVE' | 'SUSPENDED' | 'CLOSED';
      effectiveFrom: string;
      effectiveTo?: string;
    };

    export type RiskBand = 'R0' | 'R1' | 'R2' | 'R3' | 'R4';

    export type AuthorityTuple = {
      action: string;
      object: string;
      scope: string;
      purpose?: string;
      jurisdiction: string;
      validFrom?: string;
      validTo?: string;
      conditions?: Record<string, string | number | boolean>;
      risk?: RiskBand;
    };

    export type AuthoritySnapshotRef = {
      authorityRef: string;
      sourceRef: string;
      tuples: AuthorityTuple[];
    };

    export type MemoryClass =
      | 'PERSONAL'
      | 'ROLE'
      | 'INSTITUTIONAL'
      | 'PROGRAMME'
      | 'LOCATION'
      | 'ASSET'
      | 'REGULATORY'
      | 'PUBLIC';

    export type MemorySnapshotRef = {
      memoryId: string;
      memoryClass: MemoryClass;
      custodianRef: string;
      institutionId?: string;
      portability:
        | 'NON_PORTABLE'
        | 'REFERENCE_ONLY'
        | 'TRANSFER_REVIEW'
        | 'PORTABLE';
      legalHold?: boolean;
      retentionRuleRef?: string;
    };

    export type OrganisationSnapshot = {
      snapshotId: string;
      asOf: string;
      institutionId: string;
      principals: PrincipalRef[];
      institutions: InstitutionSnapshotRef[];
      roles: RoleSnapshotRef[];
      locations: LocationSnapshotRef[];
      relationships: RelationshipSnapshot[];
      assignments: AssignmentSnapshot[];
      authorityRefs: AuthoritySnapshotRef[];
      memoryRefs: MemorySnapshotRef[];
      sourceHash: string;
    };

The corrected transition contract is:

    export type ProposedSuccessorTarget = {
      successorKey: string;
      targetPrincipalRef?: string;
      targetRoleRef: string;
      targetInstitutionRef: string;
      targetLocationRef?: string;
      proposedAuthorityRefs: string[];
    };

    export type MemoryDirective = {
      mode:
        | 'PRESERVE'
        | 'REFERENCE'
        | 'TRANSFER_CANDIDATE'
        | 'SEAL'
        | 'EXCLUDE';
      scopeRefs?: string[];
    };

    export type TransitionOperation =
      | 'KEEP'
      | 'REMAP'
      | 'MERGE'
      | 'SPLIT'
      | 'PROMOTE'
      | 'TRANSFER'
      | 'SUSPEND'
      | 'CLOSE'
      | 'CREATE';

    export type TransitionProposal = {
      proposalId: string;
      operation: TransitionOperation;
      predecessorAssignmentIds: string[];
      targetPrincipalRef?: string;
      targetRoleRef?: string;
      targetInstitutionRef?: string;
      targetLocationRef?: string;
      proposedAuthorityRefs?: string[];
      successors?: ProposedSuccessorTarget[];
      memoryDirective?: MemoryDirective;
      rationale?: string;
    };

    export type ProposedTransitionSet = {
      transitionSetId: string;
      effectiveAt: string;
      sourceSnapshotId: string;
      proposals: TransitionProposal[];
      proposerRef: string;
      authorityBasisRefs: string[];
    };

The package must return a `ReconstitutionSimulation` rather than modify input. The semantic output must contain decisions, blockers, warnings and an operation count summary. The receipt carries the same semantic result status and counts plus input hashes, engine identity, `outputHash`, the two hard-coded false effect flags, and `generatedAt`.

## File Structure

Create these files. Do not put VSR-specific types inside `packages/agents-core`.

    packages/warden-reconstitution/package.json
    packages/warden-reconstitution/tsconfig.json
    packages/warden-reconstitution/tsconfig.test.json
    packages/warden-reconstitution/src/index.ts
    packages/warden-reconstitution/src/contracts/types.ts
    packages/warden-reconstitution/src/contracts/schemas.ts
    packages/warden-reconstitution/src/validation/result.ts
    packages/warden-reconstitution/src/validation/validate.ts
    packages/warden-reconstitution/src/canonical/stable-json.ts
    packages/warden-reconstitution/src/canonical/domain-canonicalize.ts
    packages/warden-reconstitution/src/hashing/hash.ts
    packages/warden-reconstitution/src/findings/codes.ts
    packages/warden-reconstitution/src/findings/finding.ts
    packages/warden-reconstitution/src/normalization/resolve.ts
    packages/warden-reconstitution/src/normalization/successor-intent.ts
    packages/warden-reconstitution/src/lineage/lineage.ts
    packages/warden-reconstitution/src/authority/diff.ts
    packages/warden-reconstitution/src/memory/disposition.ts
    packages/warden-reconstitution/src/conflicts/detect.ts
    packages/warden-reconstitution/src/invariants/evaluate.ts
    packages/warden-reconstitution/src/simulation/semantic-payload.ts
    packages/warden-reconstitution/src/simulation/simulate.ts
    packages/warden-reconstitution/src/receipts/receipt.ts
    packages/warden-reconstitution/test/helpers/fixtures.ts
    packages/warden-reconstitution/test/contracts/validation.test.ts
    packages/warden-reconstitution/test/canonical/canonical.test.ts
    packages/warden-reconstitution/test/normalization/successor-intent.test.ts
    packages/warden-reconstitution/test/lineage/lineage.test.ts
    packages/warden-reconstitution/test/authority/diff.test.ts
    packages/warden-reconstitution/test/memory/disposition.test.ts
    packages/warden-reconstitution/test/conflicts/conflicts.test.ts
    packages/warden-reconstitution/test/invariants/invariants.test.ts
    packages/warden-reconstitution/test/scenarios/operations.test.ts
    packages/warden-reconstitution/test/scenarios/negative.test.ts
    packages/warden-reconstitution/test/determinism/determinism.test.ts
    packages/warden-reconstitution/test/receipts/receipt.test.ts
    packages/warden-reconstitution/test/architecture/no-side-effects.test.ts

Modify:

    tsc-multi.json
    pnpm-lock.yaml

`pnpm-lock.yaml` is modified only by pnpm after adding the Zod dependency; never hand-edit it.

## Interfaces and Dependencies

The public validation functions consume `unknown` so callers can safely validate decoded JSON:

    export type ValidationIssue = {
      path: string;
      message: string;
    };

    export type ValidationResult<T> =
      | { ok: true; value: T }
      | { ok: false; issues: ValidationIssue[] };

    export function validateOrganisationSnapshot(
      input: unknown,
    ): ValidationResult<OrganisationSnapshot>;

    export function validateTransitionSet(
      input: unknown,
    ): ValidationResult<ProposedTransitionSet>;

The hashing API is:

    export function computeSnapshotHash(snapshot: OrganisationSnapshot): string;
    export function computeTransitionSetHash(set: ProposedTransitionSet): string;
    export function deriveSimulationId(
      snapshotHash: string,
      transitionSetHash: string,
    ): string;
    export function sha256Hex(value: string): string;

`computeSnapshotHash` canonicalizes a copy with `sourceHash` omitted. It must verify against `snapshot.sourceHash` before semantic simulation. `computeTransitionSetHash` canonicalizes the entire transition set. `deriveSimulationId` implements exactly:

    WRSIM- + first 24 lowercase hex characters of
    SHA-256(
      'WARDEN-RECONSTITUTION-ENGINE-001\n' +
      '0.1.0\n' +
      snapshotHash + '\n' +
      transitionSetHash
    )

Reference resolution is exact and local:

    export type ResolvedContext = {
      principalsById: Map<string, PrincipalRef>;
      institutionsById: Map<string, InstitutionSnapshotRef>;
      rolesById: Map<string, RoleSnapshotRef>;
      locationsById: Map<string, LocationSnapshotRef>;
      relationshipsById: Map<string, RelationshipSnapshot>;
      assignmentsById: Map<string, AssignmentSnapshot>;
      authorityById: Map<string, AuthoritySnapshotRef>;
      memoryById: Map<string, MemorySnapshotRef>;
    };

    export function buildResolvedContext(snapshot: OrganisationSnapshot): ResolvedContext;

Normalization produces no effects:

    export type NormalizedSuccessor = {
      successorKey: string;
      principalRef: string;
      roleRef: string;
      institutionRef: string;
      locationRef?: string;
      proposedAuthorityRefs: string[];
      predecessorAssignmentIds: string[];
      relationshipMode: 'REUSE' | 'CREATE';
    };

    export type SuccessorIntent = {
      proposalId: string;
      operation: TransitionOperation;
      predecessors: AssignmentSnapshot[];
      successors: NormalizedSuccessor[];
      memoryDirective?: MemoryDirective;
    };

    export function normalizeProposal(
      proposal: TransitionProposal,
      set: ProposedTransitionSet,
      context: ResolvedContext,
    ): { intent?: SuccessorIntent; findings: SimulationFinding[] };

Operation rules are exact. `KEEP` produces one successor equivalent to the predecessor and reuses its relationship. `REMAP` produces one successor with changed target role/unit fields and inherited principal. `MERGE` requires at least two predecessors; if they have different principals, `targetPrincipalRef` is mandatory; target authority is explicit and never a union. `SPLIT` requires one predecessor, at least two `successors`, and independently resolves each. `PROMOTE` produces one successor, inherits principal, and supersedes the old assignment. `TRANSFER` inherits principal; if target institution differs, `relationshipMode` is `CREATE`. `SUSPEND` produces no new relationship and marks the existing assignment's proposed state suspended. `CLOSE` produces no successor assignment. `CREATE` requires zero predecessors, `targetPrincipalRef`, target role, target institution, and explicit authority basis.

Lineage output is:

    export type ProposedRelationship = {
      relationshipId: string;
      digitalMeId: string;
      institutionId: string;
      predecessorRelationshipIds: string[];
      effectiveFrom: string;
    };

    export type ProposedAssignment = {
      assignmentId: string;
      digitalMeId: string;
      relationshipId: string;
      roleId: string;
      institutionId: string;
      locationId?: string;
      authorityRefs: string[];
      effectiveFrom: string;
      status: 'ACTIVE' | 'SUSPENDED' | 'CLOSED';
      predecessorAssignmentIds: string[];
    };

    export type RelationshipLineageProjection = {
      preservedRelationshipIds: string[];
      proposedRelationships: ProposedRelationship[];
    };

    export type AssignmentLineageProjection = {
      predecessorAssignmentIds: string[];
      proposedAssignments: ProposedAssignment[];
      predecessorDisposition: 'PRESERVE' | 'SUPERSEDE' | 'SUSPEND' | 'CLOSE';
    };

Proposed IDs are deterministic, not random. Build them as `WRREL-` or `WRASSIGN-` plus the first 20 hex characters of SHA-256 over canonical lineage inputs including simulation ID, proposal ID and successor key. This keeps golden fixtures stable.

Authority diff types are:

    export type AuthorityDiffKind =
      | 'ADDED'
      | 'REMOVED'
      | 'NARROWED'
      | 'EXPANDED'
      | 'UNCHANGED'
      | 'CONDITION_CHANGED'
      | 'SOURCE_CHANGED';

    export type AuthorityDiffEntry = {
      kind: AuthorityDiffKind;
      before?: AuthorityTuple;
      after?: AuthorityTuple;
      risk: RiskBand;
    };

    export type AuthorityDiff = {
      entries: AuthorityDiffEntry[];
      highestRisk: RiskBand;
    };

R0.1 scope comparison uses a deliberately bounded deterministic rule rather than a general ontology. Exact equal tuple except source yields `SOURCE_CHANGED`; exact equal action/object/scope/purpose/jurisdiction/time but changed conditions yields `CONDITION_CHANGED`. For known fixture scopes, a scope is wider only when the target scope string is a declared ancestor in the fixture's `scopeHierarchy` comparison input. Do not infer geographic or organisational hierarchy from names. To avoid adding a new snapshot field, `computeAuthorityDiff` accepts an optional explicit `ScopeHierarchy` supplied internally by the scenario fixture or `SimulationOptions`; when absent, a non-equal scope for the same action/object is represented as one `REMOVED` plus one `ADDED`, not guessed as `EXPANDED`. Explicit authority tuples marked risk `R3` or `R4` that are `ADDED` or `EXPANDED` produce warning `HIGH_RISK_AUTHORITY_EXPANSION`.

Memory output is:

    export type MemoryDispositionState =
      | 'PRESERVE'
      | 'REFERENCE'
      | 'TRANSFER_CANDIDATE'
      | 'SEAL'
      | 'EXCLUDE'
      | 'REVIEW_REQUIRED';

    export type MemoryDisposition = {
      memoryId: string;
      disposition: MemoryDispositionState;
      reason: string;
    };

Rules are deterministic. `legalHold: true` can never result in `EXCLUDE`; it yields `SEAL` unless the explicit directive is `PRESERVE`. `PERSONAL` memory defaults to `EXCLUDE` on successor transfer. `REFERENCE_ONLY` defaults to `REFERENCE`. `TRANSFER_REVIEW` defaults to `TRANSFER_CANDIDATE`. `PORTABLE` follows the explicit directive when it does not violate legal hold. Missing/ambiguous applicable scope yields `REVIEW_REQUIRED`. Memory classification never creates authority.

Findings use stable codes:

    export type FindingCode =
      | 'IDENTITY_UNRESOLVED'
      | 'IDENTITY_REWRITE_ATTEMPT'
      | 'RELATIONSHIP_UNRESOLVED'
      | 'ASSIGNMENT_UNRESOLVED'
      | 'AUTHORITY_BASIS_MISSING'
      | 'TARGET_ROLE_UNRESOLVED'
      | 'TARGET_INSTITUTION_UNRESOLVED'
      | 'JURISDICTION_UNRESOLVED'
      | 'MEMORY_SCOPE_AMBIGUOUS'
      | 'INVALID_PREDECESSOR_COUNT'
      | 'AUTHORITY_ESCALATION_UNSUPPORTED'
      | 'HISTORICAL_MUTATION_ATTEMPT'
      | 'DUPLICATE_SUCCESSOR_PROPOSAL'
      | 'CONFLICTING_PREDECESSOR_DISPOSITION'
      | 'AUTHORITY_SOURCE_CONFLICT'
      | 'TEMPORAL_AUTHORITY_COLLISION'
      | 'MEMORY_DIRECTIVE_CONFLICT'
      | 'HIGH_RISK_AUTHORITY_EXPANSION';

    export type SimulationFinding = {
      severity: 'WARNING' | 'BLOCKER';
      code: FindingCode;
      proposalId?: string;
      subjectRef?: string;
      message: string;
      evidenceRefs?: string[];
      details?: Record<string, unknown>;
    };

The main API is:

    export type SimulationOptions = {
      receiptGeneratedAt?: string;
      scopeHierarchy?: Record<string, string[]>;
    };

    export function simulateReconstitution(
      snapshot: OrganisationSnapshot,
      transitionSet: ProposedTransitionSet,
      options?: SimulationOptions,
    ): ReconstitutionSimulation;

External malformed JSON must be passed through the public validators first. `simulateReconstitution` may throw `TypeError` only when a caller bypasses those validators and supplies structurally malformed values that make a typed call nonsensical. Valid structural inputs with governance problems must return `BLOCKED` plus stable findings.

Receipt verification is:

    export type ReceiptVerification = {
      valid: boolean;
      errors: string[];
    };

    export function verifySimulationReceipt(
      simulation: ReconstitutionSimulation,
    ): ReceiptVerification;

It recomputes `simulationId`, semantic `outputHash`, receipt status/counts and checks both effect flags are false.

## Plan of Work

### Milestone 1 — Package scaffold, corrected contracts, and runtime validation

At the end of this milestone the monorepo recognizes a private `@vsr/warden-reconstitution` package, external JSON can be validated into the corrected R0.1 contracts, and the package compiles without any simulation behavior yet.

First create a failing validation test at `packages/warden-reconstitution/test/contracts/validation.test.ts`. Use Vitest and assert that `CREATE` without `targetPrincipalRef` and `SPLIT` with fewer than two successor targets are rejected, while a minimal valid corrected snapshot and transition set pass. The core test should contain this shape:

    import { describe, expect, it } from 'vitest';
    import {
      validateOrganisationSnapshot,
      validateTransitionSet,
    } from '../../src/index';
    import { makeSnapshot, makeTransitionSet } from '../helpers/fixtures';

    describe('R0.1 contract validation', () => {
      it('accepts a corrected snapshot with exact reference catalogues', () => {
        expect(validateOrganisationSnapshot(makeSnapshot()).ok).toBe(true);
      });

      it('rejects CREATE without a target principal', () => {
        const set = makeTransitionSet({
          proposals: [{
            proposalId: 'P-CREATE',
            operation: 'CREATE',
            predecessorAssignmentIds: [],
            targetRoleRef: 'ROLE-DATA',
            targetInstitutionRef: 'ORG-ALPHA',
            proposedAuthorityRefs: ['AUTH-DATA'],
          }],
        });
        const result = validateTransitionSet(set);
        expect(result.ok).toBe(false);
      });

      it('rejects SPLIT with fewer than two successors', () => {
        const set = makeTransitionSet({
          proposals: [{
            proposalId: 'P-SPLIT',
            operation: 'SPLIT',
            predecessorAssignmentIds: ['WA-STORE-17'],
            successors: [{
              successorKey: 'one',
              targetRoleRef: 'ROLE-STORE',
              targetInstitutionRef: 'ORG-ALPHA',
              proposedAuthorityRefs: ['AUTH-STORE'],
            }],
          }],
        });
        const result = validateTransitionSet(set);
        expect(result.ok).toBe(false);
      });
    });

Run from repository root:

    CI=1 NODE_ENV=test pnpm exec vitest run packages/warden-reconstitution/test/contracts/validation.test.ts

Before implementation expect failure because the package or exports do not exist.

Create `package.json` with `private: true`, `version: 0.1.0`, `main: dist/index.js`, `types: dist/index.d.ts`, scripts `build: tsc` and `build-check: tsc --noEmit -p ./tsconfig.test.json`, and dependency `zod` using the same compatible range already present in the monorepo (`^3.25.40 || ^4.0`). Create package `tsconfig.json` extending `../../tsconfig.json`, with `outDir: ./dist`, `rootDir: ./src`, and test exclusion. Create `tsconfig.test.json` including `src/**/*.ts` and `test/**/*.ts`. Add the new package tsconfig to root `tsc-multi.json`. Run `pnpm install` once to update the workspace lockfile.

Implement the corrected domain types in `src/contracts/types.ts`, Zod schemas in `src/contracts/schemas.ts`, `ValidationResult` in `src/validation/result.ts`, and converter functions in `src/validation/validate.ts`. Use `superRefine` for operation-specific rules: `CREATE` zero predecessors + target principal; `SPLIT` exactly one predecessor + at least two unique successor keys + no top-level successor target fields; non-SPLIT rejects non-empty `successors`; `MERGE` requires at least two predecessors; `KEEP`, `REMAP`, `PROMOTE`, `TRANSFER`, `SUSPEND`, `CLOSE` require exactly one predecessor. Validate ISO timestamps with `z.string().datetime({ offset: true })` or an equivalent strict ISO parser that accepts `Z` and explicit offsets. Export types and validators from `src/index.ts`.

Re-run the focused test and expect PASS. Then run:

    pnpm -F @vsr/warden-reconstitution build-check
    pnpm -F @vsr/warden-reconstitution build

Both must exit 0. Commit with:

    git add packages/warden-reconstitution tsc-multi.json pnpm-lock.yaml
    git commit -m "feat(warden): scaffold reconstitution contracts"

### Milestone 2 — Canonical JSON, input hashes, and deterministic simulation identity

At the end of this milestone semantically equivalent snapshot/transition inputs have stable hashes independent of object-key order and set-like array ordering, and invalid `sourceHash` values are detectable.

Write `test/canonical/canonical.test.ts` first. Construct two equivalent snapshots with reversed `principals`, `roles`, `locations`, `relationships`, `assignments`, `authorityRefs`, and `memoryRefs` arrays and with object keys inserted in different orders. Assert `computeSnapshotHash(a) === computeSnapshotHash(b)`. Construct transition sets with proposal arrays in different input order and assert equal transition-set hashes. Assert `deriveSimulationId` matches the literal derivation formula. Include a test that `stableJson` throws on `NaN`.

The main test should include:

    expect(computeSnapshotHash(snapshotA)).toBe(computeSnapshotHash(snapshotB));
    expect(computeTransitionSetHash(setA)).toBe(computeTransitionSetHash(setB));
    expect(deriveSimulationId('a'.repeat(64), 'b'.repeat(64)))
      .toMatch(/^WRSIM-[0-9a-f]{24}$/);
    expect(() => stableJson({ invalid: Number.NaN })).toThrow(TypeError);

Run the focused test and verify failure because hashing functions are absent.

Implement `src/canonical/stable-json.ts` as recursive deterministic serialization: finite numbers only, arrays preserve their supplied order, plain-object keys sort lexicographically, properties whose value is `undefined` are omitted, and unsupported values such as functions/symbols/bigints throw `TypeError`. Implement `src/canonical/domain-canonicalize.ts` to clone and sort the domain's set-like arrays by stable IDs. Proposals sort by the approved operation precedence (`CLOSE`, `SUSPEND`, `TRANSFER`, `PROMOTE`, `SPLIT`, `MERGE`, `REMAP`, `KEEP`, `CREATE`) then `proposalId`; predecessor IDs, authority-ref lists, and SPLIT successors sort deterministically. Do not mutate caller objects.

Implement `src/hashing/hash.ts` with Node `createHash('sha256')`. `computeSnapshotHash` must omit `sourceHash`; `computeTransitionSetHash` uses the canonicalized complete transition set. `deriveSimulationId` must implement the approved newline-delimited formula exactly.

Re-run the focused tests. Add one immutability assertion using `structuredClone` before canonicalization and `expect(snapshot).toEqual(before)` after hashing. Run package build-check, then commit:

    git add packages/warden-reconstitution/src/canonical packages/warden-reconstitution/src/hashing packages/warden-reconstitution/test/canonical packages/warden-reconstitution/src/index.ts
    git commit -m "feat(warden): add deterministic canonical hashing"

### Milestone 3 — Exact resolution and normalized successor intents

At the end of this milestone every structurally valid proposal becomes either a normalized `SuccessorIntent` or a stable set of findings. No role, institution, location, assignment, relationship, authority or principal is inferred by name.

Write `test/normalization/successor-intent.test.ts` first. Cover at minimum: `CREATE` resolves its explicit principal; inherited-principal operations reject a contradictory `targetPrincipalRef` with `IDENTITY_REWRITE_ATTEMPT`; cross-institution `TRANSFER` sets `relationshipMode: 'CREATE'`; `SPLIT` produces two independently resolved successors; multi-principal `MERGE` without `targetPrincipalRef` blocks; unresolved target role returns `TARGET_ROLE_UNRESOLVED`; unresolved location returns `JURISDICTION_UNRESOLVED`; missing target authority on an authority-creating operation returns `AUTHORITY_BASIS_MISSING`.

Representative assertions:

    const transfer = normalizeProposal(proposal, set, context);
    expect(transfer.findings).toEqual([]);
    expect(transfer.intent?.successors[0].relationshipMode).toBe('CREATE');

    const rewrite = normalizeProposal(rewriteProposal, set, context);
    expect(rewrite.findings.map(f => f.code)).toContain('IDENTITY_REWRITE_ATTEMPT');

Implement `src/findings/codes.ts` and `src/findings/finding.ts` first so normalizers return stable machine codes. Implement `src/normalization/resolve.ts` to build exact `Map` indexes and reject duplicate IDs when called against typed input because duplicate canonical identities are a programmer/data-integrity fault. Implement `src/normalization/successor-intent.ts` with one explicit switch over all nine operations. Do not share an implicit "default" branch; adding an operation must cause a TypeScript exhaustive-check error until handled.

Authority-basis semantics are conservative. An operation that introduces a new assignment or changes role/institution/location requires explicit `proposedAuthorityRefs` (or per-successor authority refs for SPLIT), and every referenced authority must exist in `context.authorityById`. `KEEP`, `SUSPEND`, and `CLOSE` may rely on predecessor authority because they do not create broader future authority. `REMAP` may only omit target authority when role, institution and location are unchanged; otherwise require it.

Run focused tests, then build-check, then commit:

    git add packages/warden-reconstitution/src/findings packages/warden-reconstitution/src/normalization packages/warden-reconstitution/test/normalization packages/warden-reconstitution/src/index.ts
    git commit -m "feat(warden): normalize reconstitution proposals"

### Milestone 4 — Relationship and assignment lineage projections

At the end of this milestone normalized intents deterministically project historical continuity without mutating history.

Write `test/lineage/lineage.test.ts`. Cover promotion, cross-institution transfer, close, suspend, split and merge. Assert promotion's predecessor assignment disposition is `SUPERSEDE`; cross-institution transfer preserves the old relationship ID and proposes a new deterministic relationship ID; same-institution transitions reuse the existing relationship; `CLOSE` has no proposed successor assignment and disposition `CLOSE`; `SUSPEND` preserves the same assignment identity in proposed state and disposition `SUSPEND`; each SPLIT successor has the predecessor assignment in lineage.

Use an exact deterministic ID helper. Proposed relationship ID material must contain `simulationId`, proposal ID, successor key, principal and institution. Proposed assignment ID material must contain `simulationId`, proposal ID, successor key, predecessor IDs, principal, role, institution and location. Hash with SHA-256 and prefix `WRREL-` or `WRASSIGN-`, using first 20 lowercase hex characters.

Implement `src/lineage/lineage.ts` exposing:

    export function projectLineage(
      intent: SuccessorIntent,
      context: ResolvedContext,
      simulationId: string,
      effectiveAt: string,
    ): {
      relationships: RelationshipLineageProjection;
      assignments: AssignmentLineageProjection;
      findings: SimulationFinding[];
    };

Historical snapshots are read-only. Any code path that would alter an existing relationship's `digitalMeId`, `institutionId`, `effectiveFrom`, or predecessor identity must return `HISTORICAL_MUTATION_ATTEMPT` rather than edit it.

Run focused tests and commit:

    git add packages/warden-reconstitution/src/lineage packages/warden-reconstitution/test/lineage
    git commit -m "feat(warden): project immutable assignment lineage"

### Milestone 5 — Authority diff, memory disposition, conflicts, and invariant gates

This milestone supplies the safety semantics. At the end, the kernel can explain authority changes, classify memory independently, detect contradictory proposal sets, and enforce INV-001 through INV-015.

Start with `test/authority/diff.test.ts`. Test exact unchanged tuples, source-only changes, condition-only changes, removal/addition, and explicit scope hierarchy expansion. Use a scope hierarchy such as `{ 'REGION-SOUTH': ['STORE-17', 'WAREHOUSE-04'] }` and assert changing `VIEW inventory` from `STORE-17` to `REGION-SOUTH` is `EXPANDED`. Without a hierarchy assert the same scope change becomes one `REMOVED` plus one `ADDED`, never a guessed expansion. Assert an added R3/R4 tuple causes highest risk R3/R4.

Implement `src/authority/diff.ts`. Tuple matching begins with `action + object`; exact equality across semantic fields gives `UNCHANGED`. Keep algorithms explicit and deterministic. Do not infer semantic scope hierarchy from string names.

Next write `test/memory/disposition.test.ts`. Assert personal memory on transfer defaults `EXCLUDE`; legal-hold memory cannot become `EXCLUDE`; `REFERENCE_ONLY` becomes `REFERENCE`; `TRANSFER_REVIEW` becomes `TRANSFER_CANDIDATE`; unresolved scope becomes `REVIEW_REQUIRED`. Implement `src/memory/disposition.ts` as a pure function over snapshot memory, proposal directive and transition context.

Next write `test/conflicts/conflicts.test.ts`. Construct one set where the same predecessor is both `CLOSE` and `PROMOTE`, one duplicate successor tuple, one incompatible memory directive over the same memory scope, and one overlapping responsibility window fixture. Assert stable blocker codes. Implement `src/conflicts/detect.ts`; it inspects the whole normalized proposal set and never resolves conflicts automatically.

Finally write `test/invariants/invariants.test.ts` for each locked invariant. The suite must explicitly prove: no identity rewrite; no historical relationship mutation; no title/qualification authority manufacture; no implicit MERGE union; no implicit institutional-memory transfer; CLOSE preserves lineage; SUSPEND preserves history; CREATE needs authority basis; no offline/degraded expansion (R0.1 has no offline override input, so attempts to encode one in details cannot change authority); simulation never marks live effect; each materially changed successor has authority provenance and effective time; blocked outcomes have stable codes; canonical replay is stable.

Implement `src/invariants/evaluate.ts` with an exported `evaluateInvariants` returning findings. Each invariant must have a named predicate or a documented branch in an exhaustive switch; do not hide fifteen rules in one opaque expression.

Run all four focused suites, then commit:

    git add packages/warden-reconstitution/src/authority packages/warden-reconstitution/src/memory packages/warden-reconstitution/src/conflicts packages/warden-reconstitution/src/invariants packages/warden-reconstitution/test/authority packages/warden-reconstitution/test/memory packages/warden-reconstitution/test/conflicts packages/warden-reconstitution/test/invariants
    git commit -m "feat(warden): enforce reconstitution safety semantics"

### Milestone 6 — Simulation orchestrator and River-ready receipt

At the end of this milestone the public `simulateReconstitution` function works end-to-end and its receipt can be independently verified.

Write `test/receipts/receipt.test.ts` first. Use a valid KEEP simulation and assert receipt engine fields, counts, hard-coded false flags, and `verifySimulationReceipt(result).valid === true`. Clone the result, alter one decision, and assert verification fails. Run with two different `receiptGeneratedAt` values and assert `simulationId` and `outputHash` stay equal while receipt `generatedAt` differs.

Implement `src/simulation/semantic-payload.ts` with one function that returns exactly the hash boundary:

    {
      sourceSnapshotId,
      sourceSnapshotHash,
      transitionSetId,
      transitionSetHash,
      engine: {
        id: 'WARDEN-RECONSTITUTION-ENGINE-001',
        version: '0.1.0',
        mode: 'SIMULATION',
      },
      status,
      decisions,
      blockers,
      warnings,
      summary,
    }

Implement `src/receipts/receipt.ts` to build/verify receipts. `generatedAt` comes from `options.receiptGeneratedAt ?? transitionSet.effectiveAt`; do not call `Date.now()` or `new Date()` inside the kernel.

Implement `src/simulation/simulate.ts` in the approved pipeline order: verify snapshot hash; build context; canonicalize/order proposals; normalize; detect cross-proposal conflicts; project lineage; compute authority diff; compute memory disposition; evaluate invariants; gather and canonically sort findings; classify `BLOCKED` if any blocker, `PASS_WITH_WARNINGS` if no blockers and at least one warning, else `PASS`; build summary; build semantic payload; hash; build receipt. The function must not mutate the snapshot or transition set.

Define `SimulationDecision` in `contracts/types.ts` as:

    export type SimulationDecision = {
      proposalId: string;
      operation: TransitionOperation;
      relationships: RelationshipLineageProjection;
      assignments: AssignmentLineageProjection;
      authority: AuthorityDiff;
      memory: MemoryDisposition[];
      findings: SimulationFinding[];
    };

Define `ReconstitutionSimulation` and receipt types exactly as the approved spec plus corrected dependencies. Export all public APIs from `src/index.ts`.

Run receipt tests and a package build-check. Commit:

    git add packages/warden-reconstitution/src/simulation packages/warden-reconstitution/src/receipts packages/warden-reconstitution/src/contracts/types.ts packages/warden-reconstitution/src/index.ts packages/warden-reconstitution/test/receipts
    git commit -m "feat(warden): simulate and verify reconstitution receipts"

### Milestone 7 — ORG-ALPHA fixtures and all nine operation scenarios

At the end of this milestone a human can see the full R0.1 capability exercised on fictional data.

Implement `test/helpers/fixtures.ts` with `ORG-ALPHA`, the five DigitalMe principals, roles `ROLE-STORE`, `ROLE-WAREHOUSE`, `ROLE-FIRE`, `ROLE-REGIONAL`, `ROLE-DATA`, locations `STORE-17`, `WAREHOUSE-04`, `REGION-SOUTH`, `HQ`, relationships and assignments for DM-001 through DM-005, and explicit authority records. The fixture helper must compute and insert its valid `sourceHash` using `computeSnapshotHash` rather than hard-code a stale value.

Write `test/scenarios/operations.test.ts` as one table-driven test with exactly nine named cases: KEEP, REMAP, MERGE, SPLIT, PROMOTE, TRANSFER, SUSPEND, CLOSE, CREATE. For each case assert status is not blocked, the operation summary count is one for the relevant operation, and the lineage semantics match the operation. Additional mandatory assertions: MERGE target authority equals only the explicitly supplied target authority refs; SPLIT returns at least two proposed assignments; PROMOTE keeps DigitalMe unchanged; cross-institution TRANSFER proposes a new relationship; SUSPEND preserves predecessor lineage; CLOSE produces no successor; CREATE uses its explicit target principal.

Do not store expected output hashes until behavior is stable. Once the scenario output is correct, capture the nine deterministic `simulationId` and `outputHash` values in the test as golden constants. Re-run once after reordering input arrays to prove the constants remain stable.

Run:

    CI=1 NODE_ENV=test pnpm exec vitest run packages/warden-reconstitution/test/scenarios/operations.test.ts

Expect nine passing cases. Commit:

    git add packages/warden-reconstitution/test/helpers packages/warden-reconstitution/test/scenarios/operations.test.ts
    git commit -m "test(warden): cover all reconstitution operations"

### Milestone 8 — Negative, determinism, immutability, and no-side-effect architecture tests

At the end of this milestone the package proves its safety claims rather than merely happy-path functionality.

Write `test/scenarios/negative.test.ts` with the required cases: implicit MERGE authority union attempt, cross-institution historical mutation attempt, CREATE without authority basis, duplicate successor, conflicting CLOSE and PROMOTE, unresolved predecessor, ambiguous memory transfer, authority expansion without source, temporal collision, and DigitalMe rewrite attempt. Each case must assert `status === 'BLOCKED'` and the exact expected finding code. Where a malformed shape should be caught structurally by public validators instead of semantic simulation, test the validator rather than force an impossible typed call.

Write `test/determinism/determinism.test.ts`. Generate semantically equivalent inputs by reversing all set-like arrays, rebuilding object properties in different insertion orders, and reversing proposal/predecessor/authority-ref ordering. Run simulation on both and assert equal `simulationId`, `outputHash`, decisions, blockers, warnings and summary. Supply different `receiptGeneratedAt` values and assert only that field differs. Freeze input with `Object.freeze` recursively or compare a `structuredClone` before/after to prove no mutation.

Write `test/architecture/no-side-effects.test.ts`. This test should statically read source files in the test process and fail if production source imports prohibited effectful modules or SDKs. The test process itself may use `node:fs` to inspect source; the production package may not. Scan `packages/warden-reconstitution/src/**/*.ts` and reject imports matching `node:fs`, `node:net`, `node:http`, `node:https`, `child_process`, database client names, `openai`, `@openai/agents`, or known broker clients. Allow only `node:crypto` as a Node effect-capable builtin. Also assert every returned receipt has both effect flags false.

The source-import test is architectural evidence, not a security sandbox. Its purpose is to prevent accidental dependency creep in R0.1.

Run all package tests:

    CI=1 NODE_ENV=test pnpm exec vitest run packages/warden-reconstitution/test

Expect every package test to pass. Commit:

    git add packages/warden-reconstitution/test
    git commit -m "test(warden): prove deterministic fail-closed simulation"

### Milestone 9 — Repository integration and final verification

At the end of this milestone R0.1 is implementation-complete on the feature branch and the evidence in this ExecPlan is current.

Run the package checks first:

    pnpm -F @vsr/warden-reconstitution build
    pnpm -F @vsr/warden-reconstitution build-check
    CI=1 NODE_ENV=test pnpm exec vitest run packages/warden-reconstitution/test

All commands must exit 0.

Then run the repository-mandated full sequence exactly:

    pnpm lint && pnpm build && pnpm -r build-check && pnpm test

If an inherited unrelated test fails, do not hide it. Record the exact failure in `Surprises & Discoveries`, prove the new package's focused checks are green, and only claim whole-repository completion after the inherited failure is either fixed within legitimate scope or independently resolved. Do not use `--no-verify` to bypass validation evidence.

Update `Progress` with UTC timestamps for each finished milestone. Add concise test evidence to `Surprises & Discoveries`. Update `Outcomes & Retrospective` with which acceptance gates passed and any deferred R0.2 concerns. Commit the living-plan update separately:

    git add docs/superpowers/plans/2026-09-02-warden-reconstitution-engine-r0.1.md
    git commit -m "docs(warden): record R0.1 verification evidence"

## Concrete Steps

Work from a clean checkout/worktree of branch `genesis-warden-reconstitution-r0.1`. At execution time, the worker must use `superpowers:using-git-worktrees` before coding if the current workspace is not already isolated. Install dependencies with `pnpm install` after creating the new package so the lockfile gains its importer. Do not edit generated `dist/` output by hand and do not commit coverage output.

For each milestone, follow test-driven development in this exact micro-cycle: create the named failing test; run only that test and observe a failure caused by the missing behavior; implement the smallest domain code required; run the focused test until it passes; run package build-check; review the diff for side effects and scope creep; commit using the specified Conventional Commit message. Do not implement later milestones in advance merely to make an earlier test pass.

The fastest smoke path after Milestone 6 is:

    CI=1 NODE_ENV=test pnpm exec vitest run \
      packages/warden-reconstitution/test/contracts/validation.test.ts \
      packages/warden-reconstitution/test/canonical/canonical.test.ts \
      packages/warden-reconstitution/test/normalization/successor-intent.test.ts \
      packages/warden-reconstitution/test/lineage/lineage.test.ts \
      packages/warden-reconstitution/test/receipts/receipt.test.ts

A successful transcript should end with all selected test files passing and process exit code 0.

## Validation and Acceptance

The implementation is acceptable only when a reviewer can observe these behaviors from tests, not merely find types in source code.

A valid KEEP fixture returns `PASS`, one KEEP decision, unchanged principal and relationship lineage, no authority expansion, and a receipt whose two effect flags are false. A promotion preserves the DigitalMe principal, closes/supersedes the old assignment in projection only, and creates a deterministic proposed successor assignment. A cross-institution transfer keeps the old relationship historical and proposes a new relationship. A split yields at least two independently resolved successor assignments. A merge never receives the union of predecessor authority unless that exact target authority is independently present in the explicit authority source. A create without authority basis blocks. A principal rewrite blocks. Conflicting predecessor dispositions block. High-risk authority expansion is surfaced as a warning rather than silently approved. Personal/institutional memory rules remain separate from authority.

Determinism acceptance requires the same semantic snapshot and transition set, after array and property reordering, to produce byte-equivalent canonical semantic output, identical `simulationId`, and identical `outputHash`. Changing only receipt `generatedAt` must not change semantic identity or hash. `verifySimulationReceipt` must reject a result after any decision payload is tampered.

Purity acceptance requires input objects to remain equal to pre-simulation clones and production source to contain no prohibited I/O/service imports. There must be no persistence schema, HTTP endpoint, Registry write adapter, River writer, device/network provisioner or agent call in `packages/warden-reconstitution`.

Final acceptance is the complete A01–A20 suite from the design specification plus the amendment-specific proofs: CREATE without predecessor inference, multi-successor SPLIT, exact target catalogue resolution, multi-principal MERGE target-principal requirement, and inherited-principal rewrite rejection.

## Idempotence and Recovery

All implementation operations are additive on the feature branch. The kernel itself is side-effect free, so tests and simulations can be rerun indefinitely without drift. If `pnpm install` is interrupted, rerun it; pnpm will reconcile the workspace and lockfile. If a focused test fails after a milestone, do not advance; use the last milestone commit as the known-good boundary and inspect only the current milestone's diff.

Golden hashes are intentionally recorded only after semantic behavior is correct. If a later change legitimately alters canonical semantics, update the golden values only after reviewing the semantic diff and recording the reason in this plan's `Decision Log`; never update hashes merely to make tests green.

If the full repository validation exposes unrelated inherited failures, preserve the feature branch state, record exact commands/output, and do not weaken the new package's tests. No rollback or cleanup step should mutate the `genesis` base branch.

## Artifacts and Notes

The feature branch already contains the approved design spec and schema amendment. The design branch name differs from the repository's nominal `genesis/<workstream>` pattern only because Git ref namespace rules make that pattern impossible while a literal `genesis` branch exists.

The most important future implementation evidence to append here is: focused package test counts; deterministic golden `simulationId`/`outputHash` examples; full validation command result; and any newly discovered ambiguity that required an explicit design decision.

## Self-Review Record

Spec coverage was checked against the full R0.1 design and schema amendment. The plan contains implementation work for all nine operations, exact local target resolution, identity immutability, relationship lineage, authority-source dependence, MERGE/SPLIT semantics, memory handling, conflict detection, fifteen invariants, canonicalization, SHA-256 hashing, deterministic IDs, receipt verification, no-persistence/no-agent boundaries, fictional fixtures, negative tests, determinism tests, and root repository validation.

Placeholder scan found no `TBD`, `TODO`, "implement later", or delegated unspecified error-handling steps. The only intentionally deferred releases are the already-approved R0.2+ successors and they are outside this plan.

Type consistency was checked across the interfaces in this document: `targetPrincipalRef`, `ProposedSuccessorTarget`, reference catalogues, `SuccessorIntent`, lineage projections, `AuthorityDiff`, `MemoryDisposition`, `SimulationFinding`, `SimulationOptions`, `ReconstitutionSimulation`, and `ReceiptVerification` use consistent names throughout.

Revision note — 2026-09-02: initial implementation plan written after user approval of the R0.1 schema corrections. The plan resolves two implementation details without expanding authority semantics: snapshot self-hash excludes `sourceHash`, and receipt time is caller-provided or defaults deterministically to the transition effective time so the pure kernel never reads a clock.
