# GSC-001 Warden OCM admission draft
Cross-repo Change Envelope: GEN-CHG-20261028-GSC001; parent governance draft genesis-stack PR #80.

The `admission.py` reference only performs deterministic **advisory policy screening**. It does not validate an identity token, sign grants, check real delegated permissions, query a production actor registry, or execute a repair. A `REVIEW_REQUIRED` status is never authority; `may_execute` is always false. Unknown actions, invalid inputs and missing fields fail closed. Security-critical and production changes require independent human review. Revocation requires a trusted policy source in production. 
Run: `cd genesis/gsc001 && python3 -m unittest test_admission.py -v`.
