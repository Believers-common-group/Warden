# GSC-001 R0.5 — staging signer lifecycle registry

Extends canonical Warden [PR #8](https://github.com/Believers-common-group/Warden/pull/8) and parent Genesis [PR #80](https://github.com/Believers-common-group/genesis-stack/pull/80).

Implements a **local persistent test-only signed-approval registry**. Enrol and revoke requests must receive Ed25519 signatures from separate, preconfigured `TRUST_CUSTODIAN` and `INDEPENDENT_REVIEWER` actors. The requested signer is prohibited from self-approving. The registry stores no private keys and prevents key-ID reactivation after revocation, duplicate nonces, expiry, unauthorised role substitution, or request edits. The append-only SQLite journal has hash linkage and ordinary DELETE/UPDATE denial.

The outputs are deliberately `TEST_ONLY_ENROLLED`, `TEST_ONLY_REVOKED` or `EXPIRED` and **do not feed a production trust store**. The two role roots are passed into the local constructor, not independently certified or hardware-protected; their actor strings are manually configured, not DigitalMe-authenticated. An administrator could replace the entire database or root keyset. Production would require a separate identity and key ceremony, managed KMS/HSM key ownership, an independently governed key-policy manifest, RBAC, revocation distribution and evidence anchoring.

This code neither replaces Warden's production grant service nor makes the R0.4 test-key proofs institutionally authoritative. The registry is a staging reference for the necessary checks, not the establishment of real signer authority. No live RiverOS writer, execution grant or automated repairs.

Tests: `cd genesis/gsc001 && python3 -m unittest test_signer_registry.py -v`.
