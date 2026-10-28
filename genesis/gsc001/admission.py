"""GSC-001 advisory Warden admission preflight; no real grants are issued."""
from datetime import datetime
import json

LEVELS={f"S{i}":i for i in range(5)}
NONAUTONOMOUS={"production_write", "secrets_read", "identity_change",
               "financial_settlement", "physical_actuation", "deployment_promote"}
ALLOWED={"read_evidence","dry_run","propose_repair","execute_repair"}
def parse(ts):
    if not isinstance(ts,str): raise ValueError("timestamp must be a string")
    try: d=datetime.fromisoformat(ts.replace("Z","+00:00"))
    except ValueError as exc: raise ValueError("invalid timestamp") from exc
    if d.tzinfo is None: raise ValueError("timezone required")
    return d

def evaluate(request, policy, now):
    """Never return an execution grant. Actual Warden grant must be separately authenticated."""
    if not isinstance(request,dict) or not isinstance(policy,dict):
        raise ValueError("bad input")
    if policy.get("schema")!="genesis.gsc001.warden-policy/v1":
        raise ValueError("unsupported policy schema")
    for key in ("request_id","actor_ref","change_id","resource_ref","action","severity","environment","evidence_ref","expires_at"):
        if not isinstance(request.get(key),str) or not request[key].strip():
            raise ValueError("missing "+key)
    if request["severity"] not in LEVELS or request["action"] not in ALLOWED:
        raise ValueError("unsupported severity/action")
    if request["environment"] not in ("local","development","staging","production"):
        raise ValueError("invalid environment")
    if not request["change_id"].startswith("GEN-CHG-"):
        raise ValueError("change id required")
    if not isinstance(request.get("requested_effects"),list) or not all(isinstance(x,str) for x in request["requested_effects"]):
        raise ValueError("invalid effects")
    reasons=[]
    if parse(request["expires_at"])<=parse(now):
        reasons.append("EXPIRED_REQUEST")
    if request["actor_ref"] in policy.get("revoked_actors",[]):
        reasons.append("ACTOR_REVOKED")
    if request["action"]=="execute_repair":
        reasons.append("NO_VERIFIED_WARDEN_GRANT")
    if any(x in NONAUTONOMOUS for x in request["requested_effects"]):
        reasons.append("PRIVILEGED_EFFECT_REQUIRES_REVIEW")
    if LEVELS[request["severity"]]<=1:
        reasons.append("HIGH_SEVERITY_INDEPENDENT_APPROVAL")
    if request["environment"]=="production" and request["action"]!="read_evidence":
        reasons.append("PRODUCTION_CHANGE_HOLD")
    if request["action"] not in policy.get("advisory_actions",[]):
        reasons.append("ACTION_NOT_IN_PREVIEW_POLICY")
    return {
        "schema":"genesis.gsc001.warden-admission/v1",
        "request_id":request["request_id"],"change_id":request["change_id"],
        "status":"DENY" if reasons else "REVIEW_REQUIRED",
        "reasons":sorted(set(reasons)),
        "authority":"NONE",
        "may_execute":False,
        "required_authority":"AUTHENTICATED_WARDEN_GRANT",
        "policy_ref":policy["policy_id"]+"@"+policy["version"]
    }
