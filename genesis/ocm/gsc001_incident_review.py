"""GSC-001 R0.3: advisory review gate for provisional recurrence candidates.

WARNING: A SHA-256 candidate digest checks consistency; it is not independent
provenance, signature validation, or a Warden permission grant.
"""
import hashlib
import json
import re

ALLOWED_CODES = {"CI_MISSING_FILE", "TOOLCHAIN_MISMATCH", "WRONG_RUNTIME_ENTRYPOINT",
                 "CI_MISSING_MODULE", "UNCLASSIFIED_LOG", "AMBIGUOUS_DIAGNOSTIC"}
UNVERIFIED = "UNVERIFIED_DIAGNOSTIC_EXCERPT"
SEVERITY = {"S0": 0, "S1": 1, "S2": 2, "S3": 3, "S4": 4}
DIGEST = re.compile(r"^[0-9a-f]{64}$")
EVENT = re.compile(r"^github-workflow-[0-9]+$")
SHA = re.compile(r"^[a-f0-9]{40}$")

def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")

def sha256(obj):
    return hashlib.sha256(canonical(obj)).hexdigest()

def review(candidate, candidate_sha256, *, occurrence_count, severity_hint="S3"):
    if not isinstance(candidate, dict) or candidate.get("schema") != "genesis.gsc001.incident-candidate/v1":
        raise ValueError("unknown incident candidate")
    if not isinstance(candidate_sha256, str) or not DIGEST.fullmatch(candidate_sha256):
        raise ValueError("candidate digest missing")
    if sha256(candidate) != candidate_sha256:
        raise ValueError("candidate payload inconsistent")
    for field in ("incident_id", "resource_ref", "target", "evidence_ref"):
        if not isinstance(candidate.get(field), str) or not candidate[field].strip():
            raise ValueError("missing " + field)
    if candidate.get("root_code") not in ALLOWED_CODES:
        raise ValueError("unknown code; hold in Alpha until taxonomy review")
    if candidate.get("classification") != UNVERIFIED:
        raise ValueError("classification attempted to claim verified diagnosis")
    if candidate.get("authority") != "NO_GRANT" or candidate.get("riveros") != "CANDIDATE_NOT_WRITTEN":
        raise ValueError("candidate claims extra authority/custody")
    if not isinstance(candidate.get("event_id"),str) or not EVENT.fullmatch(candidate["event_id"]):
        raise ValueError("bad source event")
    if not isinstance(candidate.get("head_sha"), str) or not SHA.fullmatch(candidate["head_sha"]):
        raise ValueError("bad commit")
    if any(not isinstance(candidate.get(k), str) or not DIGEST.fullmatch(candidate[k])
           for k in ("diagnostic_sha256", "observation_sha256")):
        raise ValueError("invalid evidence digests")
    if type(occurrence_count) is not int or occurrence_count < 1:
        raise ValueError("invalid occurrence count")
    if severity_hint not in SEVERITY:
        raise ValueError("invalid severity")
    if SEVERITY[severity_hint] <= 1:
        lane = "URGENT_HUMAN_RISK_REVIEW"
    elif candidate["root_code"] in {"UNCLASSIFIED_LOG", "AMBIGUOUS_DIAGNOSTIC"}:
        lane = "HOLD_UNKNOWN_DIAGNOSTIC"
    elif occurrence_count >= 2:
        lane = "ESCALATE_RECURRENT_UNVERIFIED"
    else:
        lane = "HOLD_INDEPENDENT_DIAGNOSIS"
    return {
        "schema": "genesis.gsc001.warden.incident-review/v1",
        "incident_id": candidate["incident_id"],
        "event_id": candidate["event_id"],
        "lane": lane,
        "severity_hint": severity_hint,
        "root_code": candidate["root_code"],
        "occurrence_count_reported": occurrence_count,
        "candidate_sha256": candidate_sha256,
        "diagnostic_provenance": "NOT_INDEPENDENTLY_ATTESTED",
        "incident_verification": "PENDING_INDEPENDENT_REVIEW",
        "prevention_breach": "NOT_ESTABLISHED",
        "authority": "NO_EXECUTION_GRANT",
        "execute": False,
        "deploy": False,
        "merge": False,
        "publish": False,
    }
