# GSC-001 Warden R0.3 — unverified recurrence review

Change envelope: `GEN-CHG-20261028-GSC001`. R0.3 consumes an Alpha-generated incident *candidate* and its canonical SHA-256 checksum. Candidate checksums are **not signatures**. The Alpha incident classifier itself labels its diagnostic excerpt unauthenticated, so this gate cannot mark root causes or preventive controls independently verified.

- Unknown/multiple diagnostic patterns: `HOLD_UNKNOWN_DIAGNOSTIC`.
- First provisional match: `HOLD_INDEPENDENT_DIAGNOSIS`.
- Reported repetition: `ESCALATE_RECURRENT_UNVERIFIED` to the assigned root-cause owner.
- S0/S1 severity hint: `URGENT_HUMAN_RISK_REVIEW` without granting containment actuation.

Never call the Warden grant-issuing runtime from this advisory module. Declared `prevention_control_state=VERIFIED` in an untrusted candidate does not establish prevention-control breach.

No real identity, signed actor admission, policy version attestation, expiry, revocation, repair execution, deployment, external RiverOS evidence custody or live monitor is provisioned here. Operational Warden integration is a separate approval-bound change.
