# GSC-001 Warden advisory projection R0.2

Tracks parent change envelope `GEN-CHG-20261028-GSC001`. This Python-stdlib reference is intentionally isolated from the existing pnpm/TypeScript Warden SDK. It validates severity floors and emits **ADVISORY_ONLY_NO_GRANT**. It is NOT an authenticated principal, live Warden policy admission, authority grant, or action. Production writes, merges, deploys and remediation remain forbidden by this prototype.

Before real integration, verify institution-specific actor identity, signed grants, expiry, revocation, immutable policy version and policy attestation from the actual Warden runtime. Do not treat a declared `VERIFIED` source flag as a trusted registry check. Run `python3 -m unittest discover -s tests -p test_gsc001_decision.py -v`.
