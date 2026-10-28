"""GSC-001 pure policy projection. NOT an auth server or Warden grant issuer."""
import hashlib,json,re
from datetime import datetime,timezone
LEVEL={"S0":0,"S1":1,"S2":2,"S3":3,"S4":4}
FLOORS={"AUTHORITY_BYPASS":1,"EVIDENCE_INTEGRITY":1,"UNCLASSIFIED_CI_FAILURE":2,"TOOLCHAIN_MISMATCH":3,"CI_MISSING_FILE":3,"BRANCH_PREFIX_COLLISION":3}
def digest(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(",",":")).encode()).hexdigest()
def parse_utc(s):
    if not isinstance(s,str) or not re.search(r"(Z|[+-]\d\d:\d\d)$",s):raise ValueError("timezone required")
    dt=datetime.fromisoformat(s.replace("Z","+00:00"))
    if dt.tzinfo is None:raise ValueError("timezone required")
    return dt.astimezone(timezone.utc)
def evaluate(case):
    if not isinstance(case,dict):raise ValueError("invalid case")
    for field in ("event_id","resource_ref","failure_code","severity","environment","observed_at"):
        if not isinstance(case.get(field),str) or not case[field].strip():raise ValueError("missing "+field)
    if case["severity"] not in LEVEL:raise ValueError("invalid severity")
    if case["environment"] not in ("development","staging","production"):raise ValueError("invalid environment")
    parse_utc(case["observed_at"])
    nodes=case.get("affected_nodes")
    if type(nodes)!=int or nodes<1:raise ValueError("invalid blast radius")
    if not isinstance(case.get("evidence_refs"),list) or not case["evidence_refs"] or any(not isinstance(x,str) or not x.strip() for x in case["evidence_refs"]):raise ValueError("missing evidence")
    floor=FLOORS.get(case["failure_code"],2)
    level=min(LEVEL[case["severity"]],floor,1 if nodes>=10 else 2 if nodes>=2 else 4)
    if case["environment"]=="production" and case.get("sensitive_domain") is True:level=min(level,1)
    unknown=case["failure_code"] not in FLOORS
    verified=case.get("prevention_control_state")=="VERIFIED"
    if level<=1:lane="CONTAIN_AND_ESCALATE"
    elif unknown:lane="HOLD_UNKNOWN"
    elif level==2 or verified:lane="HOLD_HUMAN_REVIEW"
    else:lane="PROPOSE_READ_ONLY_DIAGNOSTIC"
    return {"schema":"genesis.gsc001.warden.decision/v1","event_id":case["event_id"],
            "effective_severity":"S"+str(level),"lane":lane,"unknown":unknown,
            "recurrence_breach":verified,"case_sha256":digest(case),
            "authority":"ADVISORY_ONLY_NO_GRANT","execute":False,"promote":False}
