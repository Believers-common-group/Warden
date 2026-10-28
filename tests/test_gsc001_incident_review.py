import sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"genesis"/"ocm"))
from gsc001_incident_review import review,sha256

C={"schema":"genesis.gsc001.incident-candidate/v1",
"incident_id":"GSC-"+"A"*24,"event_id":"github-workflow-100",
"resource_ref":"Believers-common-group/Alpha-observer",
"head_sha":"a"*40,"workflow":"CI legacy",
"root_code":"CI_MISSING_FILE","target":"environment.yml",
"diagnostic_sha256":"b"*64,"observation_sha256":"c"*64,
"evidence_ref":"https://github.com/Believers-common-group/Alpha-observer/actions/runs/100",
"classification":"UNVERIFIED_DIAGNOSTIC_EXCERPT",
"authority":"NO_GRANT","riveros":"CANDIDATE_NOT_WRITTEN"}

class Gates(unittest.TestCase):
    def test_one_is_hold(self):
        d=review(C,sha256(C),occurrence_count=1)
        self.assertEqual(d["lane"],"HOLD_INDEPENDENT_DIAGNOSIS")
        self.assertEqual(d["authority"],"NO_EXECUTION_GRANT")
        self.assertFalse(d["execute"])
    def test_two_is_review_not_grant(self):
        d=review(C,sha256(C),occurrence_count=2)
        self.assertEqual(d["lane"],"ESCALATE_RECURRENT_UNVERIFIED")
        self.assertEqual(d["prevention_breach"],"NOT_ESTABLISHED")
        self.assertFalse(d["deploy"])
    def test_urgent_severity(self):
        d=review(C,sha256(C),occurrence_count=1,severity_hint="S0")
        self.assertEqual(d["lane"],"URGENT_HUMAN_RISK_REVIEW")
    def test_unknown_diagnostic_hold(self):
        obj={**C,"root_code":"UNCLASSIFIED_LOG"}
        self.assertEqual(review(obj,sha256(obj),occurrence_count=99)["lane"],"HOLD_UNKNOWN_DIAGNOSTIC")
    def test_bad_digest(self):
        with self.assertRaises(ValueError):review(C,"a"*64,occurrence_count=2)
    def test_no_claimed_verification(self):
        obj={**C,"classification":"VERIFIED"}
        with self.assertRaises(ValueError):review(obj,sha256(obj),occurrence_count=2)
    def test_no_custody_claim(self):
        obj={**C,"riveros":"WRITTEN"}
        with self.assertRaises(ValueError):review(obj,sha256(obj),occurrence_count=2)
    def test_no_exec_claim(self):
        obj={**C,"authority":"GRANTED"}
        with self.assertRaises(ValueError):review(obj,sha256(obj),occurrence_count=2)
    def test_no_missing_evidence_digest(self):
        obj={**C,"diagnostic_sha256":""}
        with self.assertRaises(ValueError):review(obj,sha256(obj),occurrence_count=1)
    def test_bool_count_rejected(self):
        with self.assertRaises(ValueError):review(C,sha256(C),occurrence_count=True)
    def test_unknown_root_code_rejected(self):
        obj={**C,"root_code":"RANDOM"}
        with self.assertRaises(ValueError):review(obj,sha256(obj),occurrence_count=1)
    def test_no_verified_prevention_from_hint(self):
        obj={**C,"prevention_control_state":"VERIFIED"}
        d=review(obj,sha256(obj),occurrence_count=2)
        self.assertEqual(d["prevention_breach"],"NOT_ESTABLISHED")

if __name__=="__main__":unittest.main()
