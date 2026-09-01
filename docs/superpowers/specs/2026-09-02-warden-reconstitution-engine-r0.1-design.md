# WARDEN-RECONSTITUTION-ENGINE-001 R0.1 — Design Specification

**Status:** In-chat design approved; written specification pending final user review  
**Date:** 2026-09-02  
**Repository:** `Believers-common-group/Warden`  
**Integration base:** `genesis`  
**Design branch:** `genesis-warden-reconstitution-r0.1`  
**Package:** `packages/warden-reconstitution`  

> Branch note: the repository manifest describes a `genesis/<workstream>` naming pattern, but Git cannot create `genesis/...` while a branch named `genesis` already exists. This design therefore uses the collision-safe branch name `genesis-warden-reconstitution-r0.1` without changing the architectural intent.

## 1. Purpose

`WARDEN-RECONSTITUTION-ENGINE-001 R0.1` is a deterministic, non-mutating simulation kernel for modelling organisational reconstitution across Warden assignments.

It accepts an immutable organisational snapshot plus a proposed transition set and answers:

> If these promotions, transfers, closures, creations, remappings, mergers, splits, suspensions or retained assignments were applied to this exact organisational state, what would change, what would remain, what would be blocked, and why?

R0.1 performs no live Registry mutation, no authority activation, no device reconfiguration, no network provisioning and no RiverOS write. It produces simulation decisions, lineage proposals, authority diffs, memory dispositions, findings and a River-ready simulation receipt.

## 2. Architectural position

The engine sits inside Warden's governance domain but does not become an authority source.

```text
Organisation / Registry / Files / API
              |
              v
      OrganisationSnapshot
              +
      ProposedTransitionSet
              |
              v
  WARDEN RECONSTITUTION ENGINE
              |
      deterministic simulation
              |
     +--------+---------+
     |        |         |
 decisions findings   receipt
              |
              v
          NO EFFECT
```

The engine preserves the established separation:

- DigitalMe anchors the principal.
- Relationships and assignments define institutional context.
- Warden evaluates consent, policy and authority.
- Genesis remains the identity/registry substrate.
- Synnergyze remains the orchestration/workspace layer.
- RiverOS remains the evidence/receipt path for material effects and accepted evidence.

Simulation output can describe proposed future authority but can never manufacture or exercise it.

## 3. R0.1 scope

### In scope

- Immutable organisational snapshot validation.
- Proposed transition-set validation.
- Nine transition operations.
- Predecessor and successor lineage modelling.
- Authority tuple comparison and semantic diffing.
- Memory-disposition classification.
- Conflict detection.
- Invariant evaluation.
- Deterministic canonicalization and hashing.
- Stable blocker/warning codes.
- River-ready simulation receipt generation.
- Golden fixtures, negative fixtures, determinism tests and invariant tests.

### Explicitly out of scope

- Registry writes.
- Relationship/assignment activation.
- Credential issuance or revocation.
- Device UI/profile deployment.
- Network entitlement provisioning.
- Synnergyze workspace reprovisioning.
- RiverOS persistence.
- Database ownership.
- HTTP services.
- Event brokers.
- LLM/agent inference.
- Fuzzy role matching.
- Automatic conflict resolution.
- Automatic authority-source selection.

## 4. Core design rule

The engine is:

**deterministic, pure, fail-closed, non-mutating, authority-source dependent, lineage preserving and memory-aware.**

Same semantic input must produce the same canonical semantic result and output hash.

## 5. Canonical input contracts

### 5.1 OrganisationSnapshot

```ts
export type OrganisationSnapshot = {
  snapshotId: string;
  asOf: string;
  institutionId: string;
  principals: PrincipalRef[];
  relationships: RelationshipSnapshot[];
  assignments: AssignmentSnapshot[];
  authorityRefs: AuthoritySnapshotRef[];
  memoryRefs: MemorySnapshotRef[];
  sourceHash: string;
};
```

The snapshot is immutable simulation input. The engine must not mutate any nested object supplied by the caller.

### 5.2 ProposedTransitionSet

```ts
export type ProposedTransitionSet = {
  transitionSetId: string;
  effectiveAt: string;
  sourceSnapshotId: string;
  proposals: TransitionProposal[];
  proposerRef: string;
  authorityBasisRefs: string[];
};
```

`authorityBasisRefs` may be empty for proposals that do not require new authority, but any operation that creates, expands, replaces or materially re-scopes authority must resolve an explicit authority basis before it can pass.

### 5.3 TransitionProposal

```ts
export type TransitionProposal = {
  proposalId: string;
  operation:
    | 'KEEP'
    | 'REMAP'
    | 'MERGE'
    | 'SPLIT'
    | 'PROMOTE'
    | 'TRANSFER'
    | 'SUSPEND'
    | 'CLOSE'
    | 'CREATE';

  predecessorAssignmentIds: string[];
  targetRoleRef?: string;
  targetInstitutionRef?: string;
  targetLocationRef?: string;
  proposedAuthorityRefs?: string[];

  memoryDirective?: {
    mode:
      | 'PRESERVE'
      | 'REFERENCE'
      | 'TRANSFER_CANDIDATE'
      | 'SEAL'
      | 'EXCLUDE';
    scopeRefs?: string[];
  };

  rationale?: string;
};
```

## 6. Canonical output contract

```ts
export type ReconstitutionSimulation = {
  simulationId: string;
  sourceSnapshotId: string;
  sourceSnapshotHash: string;
  transitionSetId: string;
  transitionSetHash: string;

  status: 'PASS' | 'PASS_WITH_WARNINGS' | 'BLOCKED';
  decisions: SimulationDecision[];
  blockers: SimulationFinding[];
  warnings: SimulationFinding[];

  summary: {
    keep: number;
    remap: number;
    merge: number;
    split: number;
    promote: number;
    transfer: number;
    suspend: number;
    close: number;
    create: number;
  };

  receipt: RiverReadySimulationReceipt;
};
```

Each `SimulationDecision` contains four independent projections:

1. proposed relationship lineage;
2. proposed assignment lineage;
3. proposed authority diff;
4. proposed memory disposition.

None is active authority.

## 7. Transition semantics

### KEEP
Preserve the assignment as-is in the target organisational model.

### REMAP
Keep the principal/responsibility while mapping the assignment to a new organisational role, unit, reporting structure or equivalent target reference.

### MERGE
Model multiple predecessor assignments becoming one proposed successor assignment. Authority is never implicitly unioned.

### SPLIT
Model one predecessor assignment producing multiple proposed successor assignments. Each successor requires independently resolved authority.

### PROMOTE
Close/supersede the prior assignment and propose a new assignment representing the promoted responsibility while preserving DigitalMe and historical lineage.

### TRANSFER
Move responsibility to a different unit, location or institution. A cross-institution transfer proposes a new institutional relationship; it never mutates the historical one.

### SUSPEND
Preserve assignment, history and memory while modelling executable authority as inactive for the suspension window.

### CLOSE
End an assignment without deleting historical identity, relationships, evidence, memory or lineage.

### CREATE
Propose a genuinely new assignment with no predecessor. An explicit authority basis is mandatory.

## 8. Safety semantics

### 8.1 MERGE does not union permission

If predecessor A has `VIEW + APPROVE` and predecessor B has `VIEW + OPERATE`, the engine must not infer `VIEW + APPROVE + OPERATE` for the successor. The successor authority must resolve from an explicit proposed authority source.

### 8.2 TRANSFER does not rewrite history

A cross-institution transfer from `REL-A` to `REL-B` preserves `REL-A` as historical and proposes `REL-B` as a new relationship linked by lineage where appropriate.

### 8.3 Simulation is not authority

Every R0.1 receipt must hard-code:

```text
activeAuthorityCreated = false
registryMutationPerformed = false
```

## 9. Simulation algorithm

The canonical pipeline is:

```text
1. Validate envelope
2. Resolve predecessors
3. Normalize proposals
4. Detect conflicts
5. Resolve relationship/assignment lineage
6. Resolve proposed authority references
7. Compute semantic authority diff
8. Resolve memory disposition
9. Run invariants
10. Classify decision state
11. Canonically sort semantic output
12. Hash canonical semantic result
13. Derive deterministic simulation ID
14. Build River-ready simulation receipt
```

### 9.1 Envelope validation

Reject structurally invalid simulations before proposal evaluation. Required checks include:

- snapshot ID/hash coherence;
- non-empty transition-set ID;
- source snapshot reference match;
- parseable effective time;
- identified proposer;
- unique proposal IDs within the transition set;
- recognized transition operation;
- required predecessor cardinality by operation;
- syntactically valid authority-basis references when supplied.

Operation-specific semantic validation determines whether an authority basis is mandatory.

### 9.2 Exact predecessor resolution

No fuzzy matching is permitted. A referenced assignment ID must resolve exactly against the supplied snapshot or produce `ASSIGNMENT_UNRESOLVED`.

### 9.3 Normalized successor intent

All operations compile internally to a normalized `SuccessorIntent` so downstream modules operate on one representation.

## 10. Deterministic operation evaluation order

Evaluation order is:

1. `CLOSE`
2. `SUSPEND`
3. `TRANSFER`
4. `PROMOTE`
5. `SPLIT`
6. `MERGE`
7. `REMAP`
8. `KEEP`
9. `CREATE`

This is simulation processing precedence only. It is not authority precedence. Conflicting operations on the same predecessor must be detected rather than resolved by input order.

## 11. Conflict families

### Structural conflict
Example: the same predecessor is both `PROMOTE` and `CLOSE` without an explicit higher-order transition rule.

Code: `CONFLICTING_PREDECESSOR_DISPOSITION`.

### Successor collision
Two proposals attempt to create the same successor identity/assignment tuple.

Code: `DUPLICATE_SUCCESSOR_PROPOSAL`.

### Authority contradiction
Proposed authority sources disagree and no authoritative resolution is supplied.

Code: `AUTHORITY_SOURCE_CONFLICT`.

### Temporal conflict
Overlapping authority windows collide in a context that does not explicitly permit concurrent responsibility.

Code: `TEMPORAL_AUTHORITY_COLLISION`.

### Memory conflict
Incompatible directives target the same memory scope.

Code: `MEMORY_DIRECTIVE_CONFLICT`.

R0.1 detects conflicts; it never invents a resolution.

## 12. Authority model and semantic diff

Authority is compared as semantic tuples, not raw JSON:

```text
ACTION
OBJECT/SUBJECT
SCOPE
PURPOSE
JURISDICTION
TIME
CONDITIONS
AUTHORITY SOURCE
```

Diff classifications:

- `ADDED`
- `REMOVED`
- `NARROWED`
- `EXPANDED`
- `UNCHANGED`
- `CONDITION_CHANGED`
- `SOURCE_CHANGED`

A scope change from `Store-17` to `Region-South` must classify semantically as `EXPANDED`, not merely as a changed string.

Risk signalling uses five bands:

- `R0` informational;
- `R1` low operational;
- `R2` material operational;
- `R3` sensitive/high-risk;
- `R4` reserved/exceptional.

R0.1 surfaces high-risk expansions but does not approve them.

## 13. Memory-disposition model

Memory is evaluated independently from assignment and authority.

Possible disposition states:

- `PRESERVE`
- `REFERENCE`
- `TRANSFER_CANDIDATE`
- `SEAL`
- `EXCLUDE`
- `REVIEW_REQUIRED`

The engine considers at least:

- memory class;
- custodian/owner;
- jurisdiction;
- retention rule;
- portability rule;
- legal hold;
- successor continuity need;
- privacy/minimisation constraints.

Durability classification never overrides privacy, lawful deletion, privilege, consent, minimisation or jurisdiction.

## 14. Locked invariants

- **INV-001** DigitalMe identity cannot be rewritten by role transition.
- **INV-002** Historical relationships cannot be mutated.
- **INV-003** Role title cannot manufacture authority.
- **INV-004** Qualification cannot manufacture authority.
- **INV-005** MERGE cannot implicitly union authority.
- **INV-006** TRANSFER cannot implicitly transfer institutional memory.
- **INV-007** CLOSE cannot erase evidence or lineage.
- **INV-008** SUSPEND cannot erase assignment/history.
- **INV-009** CREATE requires explicit authority basis.
- **INV-010** Offline/degraded context cannot expand authority.
- **INV-011** Simulation output cannot be treated as active authority.
- **INV-012** Every successor must point to authority provenance.
- **INV-013** Every material change must have effective-time semantics.
- **INV-014** Every blocked decision must return a stable reason code.
- **INV-015** Same semantic inputs must produce the same canonical semantic result and output hash.

## 15. Canonicalization, simulation identity and hashing

Canonicalization responsibilities:

- deterministic object-key ordering;
- deterministic ordering for set-like arrays;
- preserved ordering for sequence-sensitive arrays;
- normalized timestamps;
- normalized optional/undefined values;
- rejection of NaN/infinite numbers;
- UTF-8 canonical JSON output.

R0.1 hashing:

```text
algorithm: SHA-256
canonicalization: WARDEN-CANONICAL-JSON-R0.1
```

Canonical sorting includes:

- principals by principal ID;
- relationships by relationship ID;
- assignments by assignment ID;
- proposals by operation precedence + proposal ID;
- authority tuples by action + object + scope + source;
- memory dispositions by memory ID;
- findings by severity + code + subject reference.

### 15.1 Semantic hash boundary

The `outputHash` is computed over a canonical **semantic simulation payload** containing:

- source snapshot ID/hash;
- transition-set ID/hash;
- engine ID/version/mode;
- status;
- decisions;
- blockers;
- warnings;
- summary.

It excludes receipt-only observational metadata such as `generatedAt`, and excludes the receipt's own `outputHash` field to avoid recursive hashing.

### 15.2 Deterministic simulation ID

R0.1 derives `simulationId` deterministically after input canonicalization:

```text
simulationId =
  "WRSIM-" + first 24 lowercase hex characters of
  SHA-256(
    "WARDEN-RECONSTITUTION-ENGINE-001" + "\n" +
    "0.1.0" + "\n" +
    snapshotHash + "\n" +
    transitionSetHash
  )
```

The input hashes are lowercase hexadecimal SHA-256 strings over their respective canonical payloads. The literal newline separator is part of the derivation contract.

Therefore identical semantic inputs produce the same `simulationId`, decisions, findings, summary and `outputHash`. `generatedAt` may differ between receipt emissions without changing semantic identity or hash.

## 16. River-ready receipt

```ts
export type RiverReadySimulationReceipt = {
  receiptType: 'WARDEN_RECONSTITUTION_SIMULATION';
  simulationId: string;

  inputs: {
    snapshotId: string;
    snapshotHash: string;
    transitionSetId: string;
    transitionSetHash: string;
  };

  engine: {
    id: 'WARDEN-RECONSTITUTION-ENGINE-001';
    version: '0.1.0';
    mode: 'SIMULATION';
  };

  result: {
    status: 'PASS' | 'PASS_WITH_WARNINGS' | 'BLOCKED';
    decisionCount: number;
    blockerCount: number;
    warningCount: number;
  };

  hash: {
    algorithm: 'SHA-256';
    canonicalization: 'WARDEN-CANONICAL-JSON-R0.1';
    outputHash: string;
  };

  activeAuthorityCreated: false;
  registryMutationPerformed: false;
  generatedAt: string;
};
```

`generatedAt` is receipt metadata and does not influence `simulationId` or `outputHash`.

## 17. Package boundary

```text
packages/warden-reconstitution/
├── package.json
├── tsconfig.json
├── tsconfig.test.json
├── src/
│   ├── index.ts
│   ├── contracts/
│   ├── canonical/
│   ├── validation/
│   ├── normalization/
│   ├── lineage/
│   ├── authority/
│   ├── memory/
│   ├── conflicts/
│   ├── invariants/
│   ├── simulation/
│   ├── hashing/
│   ├── receipts/
│   └── findings/
└── test/
    ├── fixtures/
    ├── unit/
    ├── invariants/
    ├── determinism/
    └── scenarios/
```

Package name: `@vsr/warden-reconstitution`.

R0.1 remains `private: true`.

## 18. Runtime and dependency policy

The kernel has no database, HTTP, filesystem-mutation, Registry-client, River-client, event-broker or agent dependency.

Permitted baseline dependencies:

- TypeScript;
- Node.js crypto;
- Vitest for tests;
- Zod for external contract validation.

LLMs, embeddings, fuzzy matching and agent inference are prohibited inside the deterministic kernel.

## 19. Public API

```ts
export {
  simulateReconstitution,
  validateOrganisationSnapshot,
  validateTransitionSet,
  canonicalizeSimulationInput,
  computeAuthorityDiff,
  verifySimulationReceipt,
};

export type {
  OrganisationSnapshot,
  ProposedTransitionSet,
  TransitionProposal,
  ReconstitutionSimulation,
  SimulationDecision,
  SimulationFinding,
  AuthorityDiff,
  MemoryDisposition,
  RiverReadySimulationReceipt,
};
```

Primary entry point:

```ts
simulateReconstitution(
  snapshot: OrganisationSnapshot,
  transitionSet: ProposedTransitionSet,
  options?: SimulationOptions,
): ReconstitutionSimulation
```

`SimulationOptions` in R0.1 may only control deterministic presentation/validation features that do not alter authority semantics. No option may enable side effects.

## 20. Persistence policy

R0.1 contains no persistence layer. The caller owns input retrieval and output storage.

The simulator must not become another canonical store.

## 21. Error and finding model

Ordinary governance blockers are returned as structured simulation findings, not thrown exceptions.

```ts
export type SimulationFinding = {
  severity: 'WARNING' | 'BLOCKER';
  code: FindingCode;
  proposalId?: string;
  subjectRef?: string;
  message: string;
  evidenceRefs?: string[];
  details?: Record<string, unknown>;
};
```

Stable machine contract is the finding `code`, not the English message.

Initial blocker/warning catalogue includes:

- `IDENTITY_UNRESOLVED`
- `RELATIONSHIP_UNRESOLVED`
- `ASSIGNMENT_UNRESOLVED`
- `AUTHORITY_BASIS_MISSING`
- `TARGET_ROLE_UNRESOLVED`
- `TARGET_INSTITUTION_UNRESOLVED`
- `JURISDICTION_UNRESOLVED`
- `MEMORY_SCOPE_AMBIGUOUS`
- `INVALID_PREDECESSOR_COUNT`
- `AUTHORITY_ESCALATION_UNSUPPORTED`
- `HISTORICAL_MUTATION_ATTEMPT`
- `DUPLICATE_SUCCESSOR_PROPOSAL`
- `CONFLICTING_PREDECESSOR_DISPOSITION`
- `AUTHORITY_SOURCE_CONFLICT`
- `TEMPORAL_AUTHORITY_COLLISION`
- `MEMORY_DIRECTIVE_CONFLICT`
- `HIGH_RISK_AUTHORITY_EXPANSION`

Exceptions are reserved for genuine programmer/system faults.

## 22. Test fixtures

R0.1 uses a fictional `ORG-ALPHA` fixture with at least:

- `DM-001` Store Manager;
- `DM-002` Warehouse Warden;
- `DM-003` Fire Warden;
- `DM-004` Regional Manager;
- `DM-005` Data Warden;

across `STORE-17`, `WAREHOUSE-04`, `REGION-SOUTH` and `HQ`.

No sensitive real-person data is required.

### Baseline operation fixtures

- `01-keep.json`
- `02-remap.json`
- `03-merge.json`
- `04-split.json`
- `05-promote.json`
- `06-transfer.json`
- `07-suspend.json`
- `08-close.json`
- `09-create.json`

Each fixture contains snapshot, transition set, expected simulation output and expected hash.

### Negative fixtures

- merge authority-union attempt;
- cross-institution historical mutation attempt;
- create without authority basis;
- duplicate successor;
- conflicting close and promote;
- unresolved predecessor;
- ambiguous memory transfer;
- authority expansion without source;
- temporal collision;
- DigitalMe rewrite attempt.

## 23. Determinism and invariant testing

Determinism tests deliberately reorder:

- proposal arrays;
- object properties;
- relationship arrays;
- assignment arrays;

and require identical canonical semantic output and identical output hashes. Receipt emission time is explicitly excluded from semantic equality.

Required invariant properties include:

- no operation changes DigitalMe ID;
- CLOSE never deletes predecessor lineage;
- MERGE never creates authority absent from explicit target authority basis;
- blocked simulations never claim active authority;
- no R0.1 result claims Registry mutation;
- every successor with a predecessor has lineage;
- every materially changed successor has effective-time semantics.

## 24. Acceptance suite

Implementation is not R0.1-complete until all gates pass:

- **A01** all nine operations compile;
- **A02** source snapshot remains unchanged after simulation;
- **A03** DigitalMe rewrite is rejected;
- **A04** historical relationship rewrite is rejected;
- **A05** role-title authority inference is rejected;
- **A06** MERGE never implicitly unions authority;
- **A07** cross-institution TRANSFER proposes a new relationship;
- **A08** CLOSE preserves lineage;
- **A09** SUSPEND preserves assignment/history;
- **A10** CREATE without authority basis blocks;
- **A11** memory is evaluated separately from authority;
- **A12** conflicting proposals block deterministically;
- **A13** high-risk authority expansion is surfaced;
- **A14** canonical output is invariant to semantically irrelevant input ordering;
- **A15** identical semantic input produces identical `simulationId` and output hash;
- **A16** receipt states `activeAuthorityCreated=false`;
- **A17** receipt states `registryMutationPerformed=false`;
- **A18** ordinary governance failures return reason codes rather than uncaught exceptions;
- **A19** kernel performs no database/network/filesystem write;
- **A20** repository validation passes in the documented order.

## 25. Repository integration

The existing workspace already discovers `packages/*`, and Vitest discovers package projects under the same pattern.

Implementation must add `packages/warden-reconstitution/tsconfig.json` to the explicit root `tsc-multi.json` project list.

Validation order remains the repository's documented sequence:

```bash
pnpm lint && pnpm build && pnpm -r build-check && pnpm test
```

## 26. R0.1 completion boundary

R0.1 is complete when the package can take a valid snapshot and proposed transition set and produce a deterministic, independently verifiable simulation result covering all nine operations while proving:

- no live effect occurred;
- no authority was manufactured;
- historical identity/relationship lineage was preserved;
- memory was classified independently;
- conflicts and blockers were explicit;
- the canonical result can be replayed and verified.

## 27. Deferred successors

Possible later releases, intentionally excluded from this design:

- **R0.2 Controlled Execution:** approved Registry relationship/assignment writes.
- **R0.3 Provisioning:** Synnergyze workspace, device-profile and network-profile reprovisioning.
- **R0.4 Bulk Reconstitution:** high-volume organisational/M&A batch execution and reconciliation.
- **R0.5 Advisory Layer:** AI-assisted proposal generation, always upstream of deterministic simulation and never an authority source.

No deferred capability is implied or authorized by R0.1.
