import base64,os,sys,tempfile,unittest
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"genesis"/"gsc001"))
from signer_registry import TrustRegistry,canon
NOW="2026-10-30T00:10:00Z"
def b64(blob):return base64.urlsafe_b64encode(blob).decode().rstrip("=")
class TestSignerRegistry(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.keys=[Ed25519PrivateKey.generate() for _ in range(2)]
  self.pub=Ed25519PrivateKey.generate().public_key().public_bytes(Encoding.PEM,PublicFormat.SubjectPublicKeyInfo).decode()
  self.anchors={f"a-{i}":{"role":role,"actor_ref":f"approver-{i}",
      "public_key_pem":k.public_key().public_bytes(Encoding.PEM,PublicFormat.SubjectPublicKeyInfo).decode(),
      "assurance":"TEST_ONLY"} for i,(k,role) in enumerate(zip(self.keys,["TRUST_CUSTODIAN","INDEPENDENT_REVIEWER"]))}
  self.path=os.path.join(self.tmp.name,"trust.sqlite3");self.reg=TrustRegistry(self.path,self.anchors)
  self.req={"schema":"genesis.gsc001.signer-request/v1","action":"ENROLL","key_id":"key-001",
    "signer_role":"SOURCE_OWNER","actor_ref":"resource-operator","public_key_pem":self.pub,
    "issued_at":"2026-10-30T00:00:00Z","expires_at":"2026-10-31T00:00:00Z",
    "change_id":"GEN-CHG-20261028-GSC001","nonce":"unique-001"}
 def tearDown(self):self.reg.close();self.tmp.cleanup()
 def approve(self,req,inds=(0,1)):
  return [{"anchor_id":f"a-{i}","signature_b64":b64(self.keys[i].sign(canon(req)))} for i in inds]
 def submit(self,req=None,approvals=None):return self.reg.review(req or self.req,approvals if approvals is not None else self.approve(req or self.req),NOW)
 def test_two_role_enrolment(self):
  out=self.submit();self.assertEqual(out["state"],"TEST_ONLY_ENROLLED")
  self.assertEqual(self.reg.signer_state("key-001",NOW),"ENROLLED_TEST_ONLY");self.assertFalse(out["execution_grant"])
 def test_no_approvals(self):
  with self.assertRaises(ValueError):self.submit(approvals=[])
 def test_same_role_denied(self):
  with self.assertRaises(ValueError):self.submit(approvals=self.approve(self.req,(0,0)))
 def test_revocation_monotonic(self):
  self.submit();req={**self.req,"action":"REVOKE","nonce":"unique-002"}
  self.assertEqual(self.submit(req)["state"],"TEST_ONLY_REVOKED")
  self.assertEqual(self.reg.signer_state("key-001",NOW),"REVOKED")
  with self.assertRaises(ValueError):self.submit({**self.req,"nonce":"unique-003"})
 def test_revoke_unknown(self):
  with self.assertRaises(ValueError):self.submit({**self.req,"action":"REVOKE"})
 def test_revocation_binding(self):
  self.submit()
  with self.assertRaises(ValueError):self.submit({**self.req,"action":"REVOKE","nonce":"unique-002","actor_ref":"other"})
 def test_tamper_request(self):
  wrong=self.approve(self.req);altered={**self.req,"actor_ref":"attacker"}
  with self.assertRaises(ValueError):self.submit(altered,wrong)
 def test_stale_request(self):
  with self.assertRaises(ValueError):self.submit({**self.req,"issued_at":"2026-10-27T00:00:00Z"})
 def test_expired_request(self):
  with self.assertRaises(ValueError):self.submit({**self.req,"expires_at":"2026-10-29T00:00:00Z"})
 def test_key_expiry(self):
  self.submit()
  self.assertEqual(self.reg.signer_state("key-001","2026-11-01T00:00:00Z"),"EXPIRED")
 def test_replay_same_key(self):
  self.submit()
  with self.assertRaises(ValueError):self.submit()
 def test_missing_actor(self):
  with self.assertRaises(ValueError):self.submit({**self.req,"actor_ref":""})
 def test_no_self_enrol_approval(self):
  altered={**self.req,"actor_ref":"approver-0"}
  with self.assertRaises(ValueError):self.submit(altered)
 def test_append_only(self):
  self.submit()
  with self.assertRaises(Exception):self.reg.db.execute("DELETE FROM signer_event")
 def test_reopen_verify(self):
  self.submit();self.reg.close();self.reg=TrustRegistry(self.path,self.anchors)
  self.assertTrue(self.reg.verify())
 def test_corrupt_metadata(self):
  self.submit();self.reg.db.execute("DROP TRIGGER signer_no_update")
  self.reg.db.execute("UPDATE signer_event SET request_sha256='a'")
  self.assertFalse(self.reg.verify())
 def test_unknown_signer(self):self.assertEqual(self.reg.signer_state("absent",NOW),"UNKNOWN")
if __name__=="__main__":unittest.main()
