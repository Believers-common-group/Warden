import base64,os,tempfile,unittest
from copy import deepcopy
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
from signer_registry import canon
from review_dossier import review_dossier

NOW="2026-10-30T01:10:00Z"
def b64(data):return base64.urlsafe_b64encode(data).decode().rstrip("=")
class DossierTests(unittest.TestCase):
 def setUp(self):
  self.priv=[Ed25519PrivateKey.generate(),Ed25519PrivateKey.generate()]
  self.trust={f"key-{i}":{"role":r,"actor_ref":f"actor-{i}",
   "assurance":"TEST_ONLY","public_key_pem":p.public_key().public_bytes(Encoding.PEM,PublicFormat.SubjectPublicKeyInfo).decode()}
    for i,(r,p) in enumerate(zip(["SOURCE_OWNER","INDEPENDENT_REVIEWER"],self.priv))}
  self.base={"schema":"genesis.gsc001.rootcause-review/v1","incident_id":"GSC-EXAMPLE-001",
   "resource_ref":"Believers-common-group/Alpha-observer","failure_code":"CI_MISSING_FILE",
   "source_revision":"a"*40,"evidence_sha256":"b"*64,"change_id":"GEN-CHG-20261028-GSC001",
   "issued_at":"2026-10-30T01:00:00Z","expires_at":"2026-10-31T00:00:00Z"}
 def make(self,i,changes=None):
  obj={**self.base,**(changes or {}),"reviewer_actor":f"actor-{i}",
    "role":("SOURCE_OWNER" if i==0 else "INDEPENDENT_REVIEWER"),
    "decision":("DIAGNOSTIC_SUBMITTED" if i==0 else "DIAGNOSTIC_REVIEWED"),
    "nonce":f"nonce-{i}"}
  raw=canon(obj)
  return {"key_id":f"key-{i}","payload_b64":b64(raw),"signature_b64":b64(self.priv[i].sign(raw))}
 def test_two_reviewers_not_authority(self):
  r=review_dossier(self.make(0),self.make(1),self.trust,NOW)
  self.assertEqual(r["review_state"],"TEST_ONLY_TWO_PARTY_REVIEW")
  self.assertFalse(r["execution_grant"]);self.assertFalse(r["independent_institutional_review_verified"])
 def test_mismatched_evidence(self):
  with self.assertRaises(ValueError):
   review_dossier(self.make(0),self.make(1,{"evidence_sha256":"c"*64}),self.trust,NOW)
 def test_mismatched_revision(self):
  with self.assertRaises(ValueError):
   review_dossier(self.make(0),self.make(1,{"source_revision":"b"*40}),self.trust,NOW)
 def test_expiry(self):
  with self.assertRaises(ValueError):
   review_dossier(self.make(0),self.make(1,{"expires_at":"2026-10-30T01:09:00Z"}),self.trust,NOW)
 def test_wrong_role(self):
  with self.assertRaises(ValueError):
   review_dossier(self.make(1),self.make(0),self.trust,NOW)
 def test_no_self_review(self):
  with self.assertRaises(ValueError):
   review_dossier(self.make(0),self.make(0),self.trust,NOW)
 def test_tamper(self):
  x=self.make(0);x["signature_b64"]="AA"
  with self.assertRaises(ValueError):review_dossier(x,self.make(1),self.trust,NOW)
 def test_unknown_key(self):
  with self.assertRaises(ValueError):review_dossier(self.make(0),self.make(1),{},NOW)
 def test_revoked(self):
  with self.assertRaises(ValueError):
   review_dossier(self.make(0),self.make(1),self.trust,NOW,revoked={"key-1"})
 def test_non_test_anchor(self):
  trust=deepcopy(self.trust);trust["key-1"]["assurance"]="INSTITUTIONAL"
  with self.assertRaises(ValueError):review_dossier(self.make(0),self.make(1),trust,NOW)
if __name__=="__main__":unittest.main()
