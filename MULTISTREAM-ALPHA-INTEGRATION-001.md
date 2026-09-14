# MULTISTREAM-ALPHA-INTEGRATION-001

Status: canonical local integration contract. Revision: R0.1.

## Purpose

Multi-Stream is a consumer of Alpha's governed action path. It does not own authority, evidence, recovery, or applicability. Every mutation follows this order:

`intent -> Context Receipt -> Warden decision -> River reservation/denial record -> controlled execution -> observation -> effect verification -> River seal -> projection`

Registry resolution only establishes that an address or resource exists. It never authorizes an action. A denied decision cannot reach a Door, create an admission, or produce a projection.

## Existing roots and bindings

- `@warden/core` remains the only decision and executable Action Contract root.
- `@warden/river` remains the only reservation, denial, effect-evidence, and verification record root.
- The Alpha Action Gateway is the sole compiler from a Multi-Stream intent to the governed path.
- Context compilation emits a bounded Context Receipt with provenance and freshness before Warden evaluates the action.
- Work Queue references are bindings on River reservations; they are not a second scheduler or authority.
- Failures use the existing operational flow `Exception -> Reconciliation -> Recovery/Compensation`. Multi-Stream emits only taxonomy bindings: `EXECUTION_FAILED`, `OBSERVATION_FAILED`, `EFFECT_UNVERIFIED`, and `PROJECTION_FAILED`.

## Action namespace

The gateway accepts only typed identifiers under these families:

- `MULTISTREAM.CONTACT.*`
- `MULTISTREAM.CONVERSATION.*`
- `MULTISTREAM.EVENT.*`
- `MULTISTREAM.INBOX.*`
- `MULTISTREAM.COMMUNITY.*`
- `MULTISTREAM.CHANNEL.*`
- `MULTISTREAM.MODERATION.*`

The initial canonical identifiers are exported by `@warden/multistream`. New identifiers must be added to that closed list and must still compile to `@warden/core`'s `ActionContract`.

## Required invariants

1. Address resolution and Registry applicability are never treated as authorization.
2. Warden denial records River evidence but yields no executable Action Contract.
3. River reservation precedes every Door or adapter call.
4. A successful adapter response is insufficient: the effect must be observed and verified.
5. Inbox or other read-model projection occurs only after River seals verified evidence.
6. Any failed or unverified execution retains its Work Queue binding and enters the shared Exception/Reconciliation/Recovery taxonomy.
7. Actor, executor, authority, evidence, and projection identities remain distinct.

## Synthetic acceptance proofs

- A valid event address resolves, Warden denies `MULTISTREAM.EVENT.ADMIT`, no Door executes, no admission is written, and River records the denial.
- An allowed `ContactIntent` produces a Context Receipt, Warden ALLOW, River reservation, controlled adapter delivery, observed delivery, verified and sealed River evidence, and finally an Inbox projection.
