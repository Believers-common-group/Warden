import base64
import json
import sys
import unittest
from copy import deepcopy
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"genesis"/"gsc001"))
from control_proof import canonical, review_pair, verify_claim

NOW="2026-10-29T02:00:00Z"
COMMON={"schema":"genesis.gsc001.control-proof/v1",
        "control_ref":"GPAC-CI-MISSING-ENV","control_version":"0.4.0",
        "resource_ref":"Believers-common-group/Alpha-observer",
        "source_revision":"a"*40, "failure_code":"CI_MISSING_FILE",
        "environment":"staging","expires_at":"2026-10-30T00:00:00Z",
        "change_id":"GEN-CHG-20261028-GSC001",
        "evidence_sha256":"b"*64,
        "evidence_ref":"https://github.com/Believers-common-group/Alpha-observer/actions/runs/100"}
def b64(b): return base64.urlsafe_b64encode(b).decode().rstrip("=")
class TestControlProof(unittest.TestCase):
    def setUp(self):
        self.private=[Ed25519PrivateKey.generate(),Ed25519PrivateKey.generate()]
        self.keyring={}
        for index,role in enumerate(("SOURCE_OWNER","INDEPENDENT_OBSERVER")):
            pem=self.private[index].public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo).decode()
            self.keyring["k"+str(index)]={"public_key_pem":pem,"role":role,"actor_ref":role.lower()+":fixture","assurance":"TEST_ONLY"}
        self.dep={**COMMON,"kind":"DEPLOYMENT","at":"2026-10-28T14:00:00Z",
                  "issuer_actor":"source_owner:fixture","result":"APPLIED","nonce":"nonce-deploy"}
        self.check={**COMMON,"kind":"CONFORMANCE","at":"2026-10-28T15:00:00Z",
                    "issuer_actor":"independent_observer:fixture","result":"PASS","nonce":"nonce-test"}
    def sign(self,claim,index):
        raw=canonical(claim)
        return {"schema":"genesis.gsc001.signed-control-proof/v1",
                "key_id":"k"+str(index),"payload_b64":b64(raw),
                "signature_b64":b64(self.private[index].sign(raw))}
    def review(self,dep=None,check=None,incident=None,keys=None):
        return review_pair(self.sign(dep or self.dep,0),
                           self.sign(check or self.check,1),
                           keys or self.keyring,NOW,incident=incident)
    def test_match_never_grants(self):
        x=self.review()
        self.assertEqual(x["review_status"],"CRYPTOGRAPHICALLY_CONSISTENT_TEST_PROOFS")
        self.assertFalse(x["control_verified_operationally"])
        self.assertEqual(x["authority"],"NO_EXECUTION_GRANT")
        self.assertFalse(x["execute"])
    def test_after_control_suspected_not_proven(self):
        incident={"resource_ref":COMMON["resource_ref"],"source_revision":"a"*40,
                  "failure_code":"CI_MISSING_FILE","observed_at":"2026-10-28T16:00:00Z"}
        self.assertEqual(self.review(incident=incident)["prevention_control_breach"],"SUSPECTED_REVIEW_ONLY")
    def test_before_control_not_breach(self):
        incident={"resource_ref":COMMON["resource_ref"],"source_revision":"a"*40,
                  "failure_code":"CI_MISSING_FILE","observed_at":"2026-10-28T14:10:00Z"}
        self.assertEqual(self.review(incident=incident)["prevention_control_breach"],"NOT_ESTABLISHED")
    def test_wrong_source_revision_denied(self):
        incident={"resource_ref":COMMON["resource_ref"],"source_revision":"c"*40,
                  "failure_code":"CI_MISSING_FILE","observed_at":"2026-10-28T16:00:00Z"}
        with self.assertRaises(ValueError):self.review(incident=incident)
    def test_signer_role_mismatch(self):
        with self.assertRaises(ValueError):
            verify_claim(self.sign(self.dep,1),self.keyring,NOW)
    def test_unknown_signer(self):
        with self.assertRaises(ValueError):
            verify_claim(self.sign(self.dep,0),{},NOW)
    def test_revoked_signer(self):
        with self.assertRaises(ValueError):
            review_pair(self.sign(self.dep,0),self.sign(self.check,1),self.keyring,NOW,revoked={"k1"})
    def test_payload_tamper(self):
        x=self.sign(self.dep,0)
        wrong={**self.dep,"source_revision":"c"*40}
        x["payload_b64"]=b64(canonical(wrong))
        with self.assertRaises(ValueError):verify_claim(x,self.keyring,NOW)
    def test_version_mismatch(self):
        with self.assertRaises(ValueError):self.review(check={**self.check,"control_version":"0.4.1"})
    def test_wrong_env(self):
        with self.assertRaises(ValueError):self.review(check={**self.check,"environment":"production"})
    def test_same_actor(self):
        c={**self.check,"issuer_actor":self.dep["issuer_actor"]}
        with self.assertRaises(ValueError):self.review(check=c)
    def test_no_self_verification(self):
        with self.assertRaises(ValueError):
            review_pair(self.sign(self.dep,0),self.sign(self.dep,0),self.keyring,NOW)
    def test_conformance_before_deploy(self):
        with self.assertRaises(ValueError):self.review(check={**self.check,"at":"2026-10-28T13:00:00Z"})
    def test_failed_conformance(self):
        with self.assertRaises(ValueError):self.review(check={**self.check,"result":"FAIL"})
    def test_expired(self):
        with self.assertRaises(ValueError):self.review(dep={**self.dep,"expires_at":"2026-10-28T16:00:00Z"})
    def test_future_timestamp(self):
        with self.assertRaises(ValueError):self.review(dep={**self.dep,"at":"2026-11-01T10:00:00Z"})
    def test_missing_source_evidence(self):
        with self.assertRaises(ValueError):self.review(dep={**self.dep,"evidence_sha256":""})
    def test_reused_nonce(self):
        with self.assertRaises(ValueError):self.review(check={**self.check,"nonce":"nonce-deploy"})
    def test_forbid_unestablished_keyring(self):
        keys=deepcopy(self.keyring);keys["k0"]["assurance"]="REAL_CERTIFIED"
        with self.assertRaises(ValueError):self.review(keys=keys)
    def test_reject_invalid_timestamp(self):
        with self.assertRaises(ValueError):self.review(check={**self.check,"at":"2026-99-99T12:00:00Z"})
    def test_noncanonical_claim(self):
        raw=json.dumps(self.dep).encode()
        x={"schema":"genesis.gsc001.signed-control-proof/v1","key_id":"k0",
           "payload_b64":b64(raw),"signature_b64":b64(self.private[0].sign(raw))}
        with self.assertRaises(ValueError):verify_claim(x,self.keyring,NOW)
if __name__=="__main__":unittest.main()
