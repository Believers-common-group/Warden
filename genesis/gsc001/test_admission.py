import unittest
from admission import evaluate
import json
from pathlib import Path
POLICY=json.loads((Path(__file__).parent/"policy.json").read_text())
NOW="2026-10-28T12:00:00Z"
BASE={"request_id":"r1","actor_ref":"DigitalMeActor:example","change_id":"GEN-CHG-20261028-GSC001","resource_ref":"Alpha-observer@genesis","action":"propose_repair","severity":"S3","environment":"development","evidence_ref":"sha256:example","expires_at":"2026-10-28T14:00:00Z","requested_effects":[]}
class PolicyTests(unittest.TestCase):
    def decision(self,**changes):
        return evaluate({**BASE,**changes},POLICY,NOW)
    def test_advisory_only(self):
        self.assertEqual(self.decision()["status"],"REVIEW_REQUIRED")
        self.assertFalse(self.decision()["may_execute"])
    def test_no_exec_grant(self):
        r=self.decision(action="execute_repair")
        self.assertEqual(r["status"],"DENY")
        self.assertIn("NO_VERIFIED_WARDEN_GRANT",r["reasons"])
    def test_production_denied(self):
        self.assertEqual(self.decision(environment="production")["status"],"DENY")
    def test_privileged_effect_denied(self):
        self.assertEqual(self.decision(requested_effects=["financial_settlement"])["status"],"DENY")
    def test_emergency_requires_review(self):
        self.assertEqual(self.decision(severity="S0")["status"],"DENY")
    def test_expired_denied(self):
        self.assertEqual(self.decision(expires_at=NOW)["status"],"DENY")
    def test_revoked_denied(self):
        p={**POLICY,"revoked_actors":["DigitalMeActor:example"]}
        self.assertEqual(evaluate(BASE,p,NOW)["status"],"DENY")
    def test_missing_identity_denied(self):
        with self.assertRaises(ValueError):
            self.decision(actor_ref="")
    def test_naive_timestamp_rejected(self):
        with self.assertRaises(ValueError):
            self.decision(expires_at="2026-10-28T14:00:00")
    def test_unrecognized_action_denied(self):
        with self.assertRaises(ValueError):
            self.decision(action="deploy_everything")
    def test_policy_version_required(self):
        with self.assertRaises(KeyError):
            evaluate(BASE,{k:v for k,v in POLICY.items() if k!="policy_id"},NOW)
if __name__=="__main__":unittest.main()
