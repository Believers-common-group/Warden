# GSC-001 R0.2 — Warden authority boundary
Change Envelope `GEN-CHG-20261028-GSC001`; parent governance draft [genesis-stack PR #80](https://github.com/Believers-common-group/genesis-stack/pull/80).

`admission.py` provides deterministic **advisory-only** policy screening (DENY or REVIEW_REQUIRED). `signed_advisory.py` verifies pinned-test-key Ed25519 signed JSON advisories; strict canonical encoding, expiry, key revocation, nonce and intended audience are checked.

Run `cd genesis/gsc001 && python3 -m pip install cryptography==46.0.4 && python3 -m unittest test_admission.py test_signed_advisory.py -v`.

The committed PEM and signature are **test fixtures only**. The test signing private key was not committed. **Ed25519 proves possession of the corresponding private key, not institutional identity or Warden grant authority**. This module issues no signed execution grant; all `may_execute` outcomes are false. Production signing key custody, trusted DigitalMe actors, independent approvals, replay database, and real Warden runtime remain unimplemented.
