# WARDEN-RECONSTITUTION-ENGINE-001 R0.1 — Schema Amendment

**Status:** Approved design correction  
**Date:** 2026-09-02  
**Applies to:** `docs/superpowers/specs/2026-09-02-warden-reconstitution-engine-r0.1-design.md`  
**Authority:** This amendment is part of the R0.1 design baseline. Where this document conflicts with the earlier design specification, this amendment controls.

## Purpose

Implementation planning exposed three representational gaps in the approved R0.1 contracts. These corrections do not expand scope, create live authority, or alter the non-mutating simulation boundary. They make the already-approved nine operations deterministic and fully representable.

## Amendment A — OrganisationSnapshot reference catalogues

`OrganisationSnapshot` gains explicit catalogues for role, institution, and location references:

```ts
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
```

The simulator uses these catalogues for exact target resolution. `TARGET_ROLE_UNRESOLVED`, `TARGET_INSTITUTION_UNRESOLVED`, and `JURISDICTION_UNRESOLVED` therefore have deterministic semantics. No fuzzy or external lookup is permitted in R0.1.

## Amendment B — Explicit target principal

`TransitionProposal` gains:

```ts
targetPrincipalRef?: string;
```

Rules:

- `CREATE` requires `targetPrincipalRef` and zero predecessor assignments.
- A single-principal `MERGE` may omit it only when every predecessor resolves to the same DigitalMe; otherwise it is mandatory.
- `KEEP`, `REMAP`, `PROMOTE`, `TRANSFER`, `SUSPEND`, and `CLOSE` inherit the principal from their predecessor and must reject a contradictory `targetPrincipalRef` as `IDENTITY_REWRITE_ATTEMPT`.
- `SPLIT` principal targeting is expressed per successor using Amendment C.

## Amendment C — Multi-successor representation

Add:

```ts
export type ProposedSuccessorTarget = {
  successorKey: string;
  targetPrincipalRef?: string;
  targetRoleRef: string;
  targetInstitutionRef: string;
  targetLocationRef?: string;
  proposedAuthorityRefs: string[];
};
```

`TransitionProposal` gains:

```ts
successors?: ProposedSuccessorTarget[];
```

Rules:

- `SPLIT` requires exactly one predecessor and at least two `successors`.
- Each `successorKey` must be unique within the proposal.
- Each successor is independently validated for principal, role, institution, location, authority provenance, lineage, and effective-time semantics.
- Non-`SPLIT` operations reject a non-empty `successors` field as structurally invalid.
- The top-level `targetRoleRef`, `targetInstitutionRef`, `targetLocationRef`, and `proposedAuthorityRefs` are not used by `SPLIT`; supplying both representations is invalid.

## Corrected TransitionProposal

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

  targetPrincipalRef?: string;
  targetRoleRef?: string;
  targetInstitutionRef?: string;
  targetLocationRef?: string;
  proposedAuthorityRefs?: string[];

  successors?: ProposedSuccessorTarget[];

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

## Additional stable finding code

Add:

```text
IDENTITY_REWRITE_ATTEMPT
```

This is returned when a proposal attempts to change the DigitalMe principal of an inherited assignment rather than creating the appropriate new relationship/assignment lineage.

## Acceptance impact

The existing R0.1 acceptance suite remains intact and gains these explicit proofs:

- `CREATE` is representable without predecessor inference.
- `SPLIT` produces two or more independently resolved successor intents.
- target role/institution/location resolution is exact and local to the snapshot.
- multi-principal `MERGE` cannot silently choose a principal.
- inherited-principal operations reject DigitalMe rewriting.

All other R0.1 invariants, non-persistence rules, deterministic hashing rules, and `activeAuthorityCreated=false` / `registryMutationPerformed=false` requirements remain unchanged.
