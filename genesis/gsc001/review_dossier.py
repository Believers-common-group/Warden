"""GSC-001 R0.5 signed root-cause review dossier, test keys only.

Two reviewers express a scoped review of a diagnostic digest. This does not
authenticate GitHub logs, validate deployment or grant execution authority.
"""
import base64, hashlib, json
from cryptography.exceptions import InvalidSignature
from signer_registry import canon, when, decode, public_key

SCHEMA = "genesis.gsc001.rootcause-review/v1"
ROLES = {"SOURCE_OWNER", "INDEPENDENT_REVIEWER"}
OUTCOMES = {"SOURCE_OWNER":"DIAGNOSTIC_SUBMITTED",
            "INDEPENDENT_REVIEWER":"DIAGNOSTIC_REVIEWED"}
REQUIRED = {"schema","incident_id","resource_ref","failure_code","source_revision",
            "evidence_sha256","change_id","reviewer_actor","role","decision",
            "issued_at","expires_at","nonce"}
MATCH = {"incident_id","resource_ref","failure_code","source_revision",
         "evidence_sha256","change_id"}

def _signed(envelope, trust, now):
    if not isinstance(envelope,dict) or set(envelope)!={"key_id","payload_b64","signature_b64"}:
        raise ValueError("bad review envelope")
    ident=envelope["key_id"]
    if not isinstance(trust,dict) or ident not in trust:
        raise ValueError("unknown reviewer key")
    anchor=trust[ident]
    if anchor.get("assurance")!="TEST_ONLY" or anchor.get("role") not in ROLES:
        raise ValueError("non-test signer or wrong role")
    payload=decode(envelope["payload_b64"]); sig=decode(envelope["signature_b64"])
    try: public_key(anchor["public_key_pem"]).verify(sig,payload)
    except InvalidSignature as err:raise ValueError("invalid review signature") from err
    try: obj=json.loads(payload)
    except ValueError as err:raise ValueError("invalid review payload") from err
    if not isinstance(obj,dict) or canon(obj)!=payload or set(obj)!=REQUIRED:
        raise ValueError("noncanonical review payload")
    if obj["schema"]!=SCHEMA or obj["role"]!=anchor["role"] or obj["reviewer_actor"]!=anchor.get("actor_ref"):
        raise ValueError("role/actor impersonation")
    for k in ("incident_id","resource_ref","failure_code","source_revision","evidence_sha256",
              "change_id","reviewer_actor","nonce"):
        if not isinstance(obj[k],str) or not obj[k].strip():raise ValueError("missing "+k)
    if obj["decision"]!=OUTCOMES[obj["role"]]:raise ValueError("invalid review decision")
    if not obj["change_id"].startswith("GEN-CHG-") or len(obj["evidence_sha256"])!=64:
        raise ValueError("bad evidence scope")
    issued=when(obj["issued_at"]);expires=when(obj["expires_at"]);current=when(now)
    if not issued<=current<expires or (current-issued).total_seconds()>86400:
        raise ValueError("stale or expired review")
    return obj

def review_dossier(submission, independent, trust, now, *, revoked=()):
    if submission.get("key_id") in revoked or independent.get("key_id") in revoked:
        raise ValueError("revoked reviewer")
    a=_signed(submission,trust,now)
    b=_signed(independent,trust,now)
    if a["role"]!="SOURCE_OWNER" or b["role"]!="INDEPENDENT_REVIEWER":
        raise ValueError("missing independent review")
    if submission["key_id"]==independent["key_id"] or a["reviewer_actor"]==b["reviewer_actor"]:
        raise ValueError("self-review forbidden")
    if any(a[k]!=b[k] for k in MATCH):
        raise ValueError("different incident or evidence")
    if a["nonce"]==b["nonce"]:
        raise ValueError("replayed approval nonce")
    return {"schema":"genesis.gsc001.review-dossier/v1","incident_id":a["incident_id"],
            "source_revision":a["source_revision"],"resource_ref":a["resource_ref"],
            "evidence_sha256":a["evidence_sha256"],"review_state":"TEST_ONLY_TWO_PARTY_REVIEW",
            "independent_institutional_review_verified":False,
            "control_breach_verified":False,"execution_grant":False,
            "riveros_admitted":False,"authority":"NONE"}
