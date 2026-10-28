# GSC-001 R0.4 — signed prevention-control proof gate

Extends the canonical Warden R0.2 [PR #5](https://github.com/Believers-common-group/Warden/pull/5); parent Genesis change `GEN-CHG-20261028-GSC001`.

A **source-owner deployment claim** and **independent-observer conformance claim** must both have valid detached Ed25519 signatures and a caller-configured keyring with different actors, roles and key IDs. Signed claims must share control identity, control version, exact resource, exact source revision, failure class, environment and change reference; independent testing must occur after the deployment and before the proof expires.

If a later incident matches the exact control scope, this stage emits `SUSPECTED_REVIEW_ONLY`. It does **not** declare a verified prevention breach, grant Warden authority or execute a repair.

**Critical trust limitation:** the reference accepts only keyrings explicitly labelled `TEST_ONLY`. The keys in tests are ephemeral and generated at runtime. There is no enrolled institutional root of trust, independently fetched GitHub diagnostics, signed RiverOS custody, verified safe release or operational Warden runtime. Raw event attestations are not accepted here. A runtime service MUST obtain authority from a separately approved, revocable identity/governance plane; this demo cannot be promoted merely by changing `TEST_ONLY` to another string.

Controls: deny missing evidence, version mismatch, clock skew, expired signing attestations, same-actor self-certification, failed tests, untrusted keys, signature forgery and source mismatch.

```sh
cd genesis/gsc001
python3 -m unittest test_control_proof.py -v
```

Keep in DRAFT. Test-only control proof is not independent real-world confirmation.
