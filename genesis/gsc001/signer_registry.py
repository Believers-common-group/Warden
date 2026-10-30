"""GSC-001 R0.5 staged signer lifecycle — TEST ONLY, not institution enrolment.

Two independent Ed25519 test-anchor approvals bind each enrolment/revocation.
Append-only SQLite journal guards ordinary modifications, but is NOT RiverOS,
HSM-backed identity, independent external anchoring or production authority.
"""
import base64, hashlib, json, re, sqlite3
from datetime import datetime, timezone
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.serialization import load_pem_public_key
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

ROLES={"TRUST_CUSTODIAN","INDEPENDENT_REVIEWER"}
SIGNER_ROLES={"SOURCE_OWNER","INDEPENDENT_OBSERVER"}
HEX64=re.compile(r"^[a-f0-9]{64}$")
ID=re.compile(r"^[A-Za-z0-9_.:/-]{3,128}$")
OPS={"ENROLL","REVOKE"}

def canon(obj):
    return json.dumps(obj,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
def digest(obj):
    return hashlib.sha256(canon(obj)).hexdigest()
def when(value):
    if not isinstance(value,str) or not re.search(r"(Z|[+-]\d\d:\d\d)$",value):
        raise ValueError("timezone required")
    try: dt=datetime.fromisoformat(value.replace("Z","+00:00"))
    except ValueError as e:raise ValueError("invalid time") from e
    if dt.tzinfo is None:raise ValueError("timezone required")
    return dt.astimezone(timezone.utc)
def decode(value):
    if not isinstance(value,str) or not re.fullmatch(r"[A-Za-z0-9_-]+",value):raise ValueError("invalid signature format")
    try: b=base64.urlsafe_b64decode(value+"="*((-len(value))%4))
    except (ValueError,base64.binascii.Error) as e: raise ValueError("bad signature") from e
    if base64.urlsafe_b64encode(b).decode().rstrip("=")!=value:raise ValueError("noncanonical signature")
    return b
def public_key(pem):
    if not isinstance(pem,str):raise ValueError("public key required")
    try: key=load_pem_public_key(pem.encode())
    except (ValueError,TypeError) as e:raise ValueError("bad public key") from e
    if not isinstance(key,Ed25519PublicKey):raise ValueError("Ed25519 public key required")
    return key

class TrustRegistry:
    def __init__(self,path,test_anchors):
        if not isinstance(test_anchors,dict) or len(test_anchors)<2:
            raise ValueError("two test anchors required")
        self.anchors=test_anchors
        roles=set();actors=set()
        for aid,entry in test_anchors.items():
            if not ID.fullmatch(aid) or not isinstance(entry,dict) or entry.get("assurance")!="TEST_ONLY":
                raise ValueError("untrusted anchor")
            if entry.get("role") not in ROLES or not isinstance(entry.get("actor_ref"),str):
                raise ValueError("bad anchor role")
            if entry["actor_ref"] in actors:raise ValueError("same actor enrolled twice")
            public_key(entry.get("public_key_pem"))
            actors.add(entry["actor_ref"]);roles.add(entry["role"])
        if roles!=ROLES:raise ValueError("both independent roles required")
        self.db=sqlite3.connect(path,timeout=10,isolation_level=None)
        self.db.row_factory=sqlite3.Row
        self.db.execute("PRAGMA busy_timeout=10000")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS signer_event(
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            key_id TEXT NOT NULL,
            action TEXT NOT NULL,
            request_json TEXT NOT NULL,
            request_sha256 TEXT NOT NULL,
            approvals_json TEXT NOT NULL,
            previous_hash TEXT NOT NULL,
            entry_hash TEXT NOT NULL,
            nonce TEXT NOT NULL UNIQUE
        )""")
        self.db.execute("""CREATE TRIGGER IF NOT EXISTS signer_no_update BEFORE UPDATE ON signer_event
                         BEGIN SELECT RAISE(ABORT,'append only'); END""")
        self.db.execute("""CREATE TRIGGER IF NOT EXISTS signer_no_delete BEFORE DELETE ON signer_event
                         BEGIN SELECT RAISE(ABORT,'append only'); END""")
    def close(self):self.db.close()
    def _state(self,key_id):
        row=self.db.execute("SELECT action,request_json FROM signer_event WHERE key_id=? ORDER BY seq DESC LIMIT 1",(key_id,)).fetchone()
        return None if row is None else (row["action"],json.loads(row["request_json"]))
    def review(self,request,approvals,now):
        if not isinstance(request,dict) or set(request)!={"schema","action","key_id","signer_role","actor_ref",
            "public_key_pem","issued_at","expires_at","change_id","nonce"}:
            raise ValueError("unsupported request")
        if request["schema"]!="genesis.gsc001.signer-request/v1" or request["action"] not in OPS:
            raise ValueError("invalid request schema/action")
        for k in ("key_id","actor_ref","change_id","nonce"):
            if not isinstance(request[k],str) or not ID.fullmatch(request[k]):
                raise ValueError("invalid "+k)
        if not request["change_id"].startswith("GEN-CHG-") or request["signer_role"] not in SIGNER_ROLES:
            raise ValueError("invalid scope/role")
        public_key(request["public_key_pem"])
        t=when(now);issued=when(request["issued_at"]);expires=when(request["expires_at"])
        if not issued<=t<expires or (t-issued).total_seconds()>3600:
            raise ValueError("stale or expired request")
        if not isinstance(approvals,list) or len(approvals)!=2:
            raise ValueError("two approvals required")
        seen=set();seenactors=set();approved=[]
        msg=canon(request)
        for attestation in approvals:
            if not isinstance(attestation,dict) or set(attestation)!={"anchor_id","signature_b64"}:
                raise ValueError("bad approval envelope")
            aid=attestation["anchor_id"]
            if aid not in self.anchors or aid in seen:raise ValueError("duplicated or unknown signer")
            anchor=self.anchors[aid]
            if anchor["actor_ref"]==request["actor_ref"]:raise ValueError("self approval prohibited")
            if anchor["actor_ref"] in seenactors:raise ValueError("same approval actor")
            signature=decode(attestation["signature_b64"])
            try:public_key(anchor["public_key_pem"]).verify(signature,msg)
            except InvalidSignature as e:raise ValueError("invalid approval signature") from e
            seen.add(aid);seenactors.add(anchor["actor_ref"]);approved.append({"anchor_id":aid,"role":anchor["role"],
                                                "actor_ref":anchor["actor_ref"],"signature_sha256":hashlib.sha256(signature).hexdigest()})
        if {x["role"] for x in approved} != ROLES:
            raise ValueError("missing independent reviewer")
        with self.db:
            self.db.execute("BEGIN IMMEDIATE")
            previous=self._state(request["key_id"])
            if request["action"]=="ENROLL" and previous is not None:
                raise ValueError("key ID immutable; cannot re-enrol")
            if request["action"]=="REVOKE" and (previous is None or previous[0]!="ENROLL"):
                raise ValueError("key not currently enrolled")
            if request["action"]=="REVOKE":
                prev=previous[1]
                if any(request[k]!=prev[k] for k in ("signer_role","actor_ref","public_key_pem","change_id")):
                    raise ValueError("revocation does not match enrolled key")
            tail=self.db.execute("SELECT entry_hash FROM signer_event ORDER BY seq DESC LIMIT 1").fetchone()
            prior=tail["entry_hash"] if tail else "0"*64
            body={"request_sha256":digest(request),"approvals":sorted(approved,key=lambda a:a["anchor_id"]),
                  "previous_hash":prior}
            eh=digest(body)
            self.db.execute("""INSERT INTO signer_event(key_id,action,request_json,request_sha256,
               approvals_json,previous_hash,entry_hash,nonce) VALUES(?,?,?,?,?,?,?,?)""",
               (request["key_id"],request["action"],msg.decode(),body["request_sha256"],
                canon(body["approvals"]).decode(),prior,eh,request["nonce"]))
        return {"state":"TEST_ONLY_ENROLLED" if request["action"]=="ENROLL" else "TEST_ONLY_REVOKED",
                "key_id":request["key_id"],"entry_hash":eh,
                "institutional_trust":"NOT_ESTABLISHED","execution_grant":False}
    def verify(self):
        prior="0"*64;used=set()
        for row in self.db.execute("SELECT * FROM signer_event ORDER BY seq"):
            req=json.loads(row["request_json"]);appr=json.loads(row["approvals_json"])
            if row["nonce"] in used or row["key_id"]!=req["key_id"] or row["action"]!=req["action"]:
                return False
            used.add(row["nonce"])
            if digest(req)!=row["request_sha256"] or row["previous_hash"]!=prior:
                return False
            if digest({"request_sha256":row["request_sha256"],"approvals":appr,
                       "previous_hash":prior})!=row["entry_hash"]:
                return False
            prior=row["entry_hash"]
        return True
    def signer_state(self,key_id,now):
        if not self.verify():raise ValueError("ledger integrity failure")
        state=self._state(key_id)
        if state is None:return "UNKNOWN"
        op,req=state
        if op=="REVOKE":return "REVOKED"
        if when(now)>=when(req["expires_at"]):return "EXPIRED"
        return "ENROLLED_TEST_ONLY"
