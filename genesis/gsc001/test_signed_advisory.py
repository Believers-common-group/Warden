import json
from pathlib import Path
import unittest
import signed_advisory as g
HERE=Path(__file__).parent
ENV=json.loads((HERE/'signed-advisory.fixture.json').read_text())
KEYS={ENV['key_id']:(HERE/'test-public.pem').read_text()}
NOW='2026-10-28T12:00:00Z'
AUD='SYN-GSC001-R02'
class Checks(unittest.TestCase):
 def check(self,e=None,**kw):return g.verify(e or ENV,KEYS,NOW,AUD,**kw)
 def test_valid(self):self.assertEqual(self.check()['authority'],'NONE')
 def test_revoke(self):
  with self.assertRaises(ValueError):self.check(revoked=[ENV['key_id']])
 def test_replay(self):
  with self.assertRaises(ValueError):self.check(used_nonces=['demo-nonce-001'])
 def test_bad_sig(self):
  e={**ENV,'signature_b64':'AAAA'}
  with self.assertRaises(ValueError):self.check(e)
 def test_tamper(self):
  e={**ENV,'payload_b64':ENV['payload_b64'][:-1]+'A'}
  with self.assertRaises(ValueError):self.check(e)
 def test_bad_audience(self):
  with self.assertRaises(ValueError):g.verify(ENV,KEYS,NOW,'OTHER')
 def test_expired(self):
  with self.assertRaises(ValueError):g.verify(ENV,KEYS,'2027-02-01T00:00:00Z',AUD)
 def test_issued_later(self):
  with self.assertRaises(ValueError):g.verify(ENV,KEYS,'2026-10-27T00:00:00Z',AUD)
 def test_unknown_key(self):
  with self.assertRaises(ValueError):g.verify(ENV,{},NOW,AUD)
 def test_schema(self):
  with self.assertRaises(ValueError):self.check({**ENV,'schema':'wrong'})
 def test_additional_fields(self):
  with self.assertRaises(ValueError):self.check({**ENV,'auto_execute':True})
if __name__=='__main__':unittest.main()
