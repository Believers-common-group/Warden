import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"genesis"/"ocm"))
from gsc001_decision import evaluate
BASE={"event_id":"evt01","resource_ref":"Believers-common-group/Alpha-observer","failure_code":"UNCLASSIFIED_CI_FAILURE",
"severity":"S4","environment":"development","observed_at":"2026-10-28T12:00:00Z","affected_nodes":1,
"evidence_refs":["https://github.com/Believers-common-group/Alpha-observer/actions/runs/123"]}
class Rules(unittest.TestCase):
 def test_ci_floor(self):self.assertEqual(evaluate(BASE)["effective_severity"],"S2")
 def test_no_grant(self):
  d=evaluate(BASE);self.assertFalse(d["execute"]);self.assertEqual(d["authority"],"ADVISORY_ONLY_NO_GRANT")
 def test_unknown_held(self):self.assertEqual(evaluate({**BASE,"failure_code":"UNSEEN"})["lane"],"HOLD_UNKNOWN")
 def test_unknown_emergency(self):self.assertEqual(evaluate({**BASE,"failure_code":"UNSEEN","severity":"S0"})["lane"],"CONTAIN_AND_ESCALATE")
 def test_sensitive_production(self):self.assertEqual(evaluate({**BASE,"environment":"production","sensitive_domain":True})["effective_severity"],"S1")
 def test_wide_blast_radius(self):self.assertEqual(evaluate({**BASE,"affected_nodes":12})["lane"],"CONTAIN_AND_ESCALATE")
 def test_verified_breach(self):
  d=evaluate({**BASE,"failure_code":"CI_MISSING_FILE","prevention_control_state":"VERIFIED"})
  self.assertTrue(d["recurrence_breach"]);self.assertEqual(d["lane"],"HOLD_HUMAN_REVIEW")
 def test_missing_evidence(self):
  with self.assertRaises(ValueError):evaluate({**BASE,"evidence_refs":[]})
 def test_invalid_time(self):
  with self.assertRaises(ValueError):evaluate({**BASE,"observed_at":"2026-99-99T00:00:00Z"})
if __name__=="__main__":unittest.main()
