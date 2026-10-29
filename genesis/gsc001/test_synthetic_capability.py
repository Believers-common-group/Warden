"""Offline tests create a disposable in-memory key; no signing secrets are committed."""
import base64
from datetime import datetime
import hashlib
import unittest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
from synthetic_capability import SCHEMA,canonical,verify_synthetic

BEFORE={"package":"synthetic-alpha","python_runtime":"3.10","required_python":"3.11","fixture_only":True}
AFTER={**BEFORE,"python_runtime":"3.11"}
SHA=lambda b:hashlib.sha256(b).hexdigest()
NOW="2026-10-29T06:00:00Z"
def make_test_capability(**override):
    private=Ed25519PrivateKey.generate()
    key_id="TEST_ONLY_GSC001_EPHEMERAL"
    payload={
      "schema":SCHEMA,"kind":"TEST_ONLY_NOT_WARDEN_GRANT","key_id":key_id,
      "actor_ref":"TEST_ONLY:SYN_GSC001","change_id":"GEN-CHG-20261028-GSC001",
      "request_id":"synthetic-request-001","audience":"SYN_GSC001_TEST_HARNESS",
      "resource_ref":"TEST_ONLY:Alpha-observer","source_revision":"synthetic-revision-001",
      "failure_code":"TOOLCHAIN_MISMATCH",
      "operation":"SIMULATE_REVERSIBLE_COMPATIBILITY_FIX",
      "target":"compatibility.json","before_sha256":SHA(canonical(BEFORE)),
      "after_sha256":SHA(canonical(AFTER)),"nonce":"synthetic-nonce-001",
      "issued_at":"2026-10-29T00:00:00Z","expires_at":"2026-10-30T00:00:00Z",
      "sandbox_only":True,"execution_domain":"LOCAL_EPHEMERAL_FIXTURE",
      "advisory_nonce":"synthetic-advisory-001",
      "evidence_ref":"sha256:"+SHA(canonical(BEFORE))}
    payload.update(override)
    raw=canonical(payload)
    enc=lambda b:base64.urlsafe_b64encode(b).decode().rstrip("=")
    envelope={"schema":SCHEMA,"key_id":key_id,
              "payload_b64":enc(raw),"signature_b64":enc(private.sign(raw))}
    pub=private.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)
    return envelope,{key_id:pub}

class TestCapability(unittest.TestCase):
 def test_valid_synthetic_only(self):
    env,keys=make_test_capability()
    self.assertEqual(verify_synthetic(env,keys,NOW)["kind"],"TEST_ONLY_NOT_WARDEN_GRANT")
 def test_reject_signature_tamper(self):
    env,keys=make_test_capability()
    with self.assertRaises(ValueError):verify_synthetic({**env,"signature_b64":"AAAA"},keys,NOW)
 def test_reject_revocation(self):
    env,keys=make_test_capability()
    with self.assertRaises(ValueError):verify_synthetic(env,keys,NOW,revoked=[env["key_id"]])
 def test_reject_replay(self):
    env,keys=make_test_capability()
    with self.assertRaises(ValueError):verify_synthetic(env,keys,NOW,used_nonces=["synthetic-nonce-001"])
 def test_reject_real_environment(self):
    env,keys=make_test_capability(execution_domain="PRODUCTION")
    with self.assertRaises(ValueError):verify_synthetic(env,keys,NOW)
 def test_reject_operational_grant_claim(self):
    env,keys=make_test_capability(kind="WARDEN_EXECUTION_GRANT")
    with self.assertRaises(ValueError):verify_synthetic(env,keys,NOW)
 def test_reject_expiry(self):
    env,keys=make_test_capability()
    with self.assertRaises(ValueError):verify_synthetic(env,keys,"2026-10-31T00:00:00Z")
 def test_reject_wrong_audience(self):
    env,keys=make_test_capability(audience="OUTSIDE")
    with self.assertRaises(ValueError):verify_synthetic(env,keys,NOW)
 def test_reject_untrusted_key(self):
    env,_=make_test_capability()
    with self.assertRaises(ValueError):verify_synthetic(env,{},NOW)
if __name__=="__main__":unittest.main()
