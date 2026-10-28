"""GSC-001 R0.4: independent signed prevention-control proof, REVIEW ONLY.

This checks Ed25519 payload integrity and two distinct trusted-key roles.
It is NOT a Warden execution grant, live identity trust, deployment verification,
RiverOS custody, or an operational control-breach declaration.
"""
import base64
import hashlib
import json
import re
from datetime import datetime, timezone
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.serialization import load_pem_public_key

SCHEMA = "genesis.gsc001.control-proof/v1"
HEX64 = re.compile(r"^[a-f0-9]{64}$")
HEX40 = re.compile(r"^[a-f0-9]{40}$")
FIELDS = {"schema", "kind", "control_ref", "control_version", "resource_ref",
          "source_revision", "failure_code", "environment", "at", "expires_at",
          "evidence_ref", "evidence_sha256", "change_id", "issuer_actor",
          "result", "nonce"}
ENV = {"local", "development", "staging", "production"}
ROLES = {"DEPLOYMENT": "SOURCE_OWNER", "CONFORMANCE": "INDEPENDENT_OBSERVER"}

def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")

def sha(obj):
    return hashlib.sha256(canonical(obj)).hexdigest()

def instant(s):
    if not isinstance(s, str) or not re.search(r"(?:Z|[+-]\d\d:\d\d)$", s):
        raise ValueError("timezone required")
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("invalid timestamp") from exc
    if dt.tzinfo is None:
        raise ValueError("timezone required")
    return dt.astimezone(timezone.utc)

def decode(s):
    if not isinstance(s, str) or not s or not re.fullmatch(r"[A-Za-z0-9_-]+", s):
        raise ValueError("invalid base64url")
    try:
        out = base64.urlsafe_b64decode(s + "=" * ((-len(s)) % 4))
    except (ValueError, base64.binascii.Error) as exc:
        raise ValueError("invalid base64url") from exc
    if base64.urlsafe_b64encode(out).decode().rstrip("=") != s:
        raise ValueError("noncanonical base64url")
    return out

def verify_claim(envelope, keyring, now, *, revoked=()):
    """Caller-provisioned keyring is NOT itself an independently certified key store."""
    if not isinstance(envelope, dict) or set(envelope) != {"schema", "key_id", "payload_b64", "signature_b64"}:
        raise ValueError("bad envelope")
    if envelope["schema"] != "genesis.gsc001.signed-control-proof/v1":
        raise ValueError("unknown envelope schema")
    key_id = envelope["key_id"]
    if not isinstance(key_id, str) or not isinstance(keyring, dict) or key_id not in keyring or key_id in revoked:
        raise ValueError("unknown or revoked signer")
    trusted = keyring[key_id]
    if not isinstance(trusted, dict) or trusted.get("role") not in ROLES.values() or trusted.get("assurance") != "TEST_ONLY":
        raise ValueError("unestablished trust anchor")
    raw = decode(envelope["payload_b64"])
    sig = decode(envelope["signature_b64"])
    public = load_pem_public_key(trusted["public_key_pem"].encode())
    try:
        public.verify(sig, raw)
    except (InvalidSignature, ValueError) as exc:
        raise ValueError("invalid signature") from exc
    try:
        claim = json.loads(raw)
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError("invalid claim json") from exc
    if not isinstance(claim, dict) or canonical(claim) != raw or set(claim) != FIELDS:
        raise ValueError("noncanonical or unsupported claim")
    if claim["schema"] != SCHEMA or claim.get("kind") not in ROLES:
        raise ValueError("unknown claim kind")
    if trusted["role"] != ROLES[claim["kind"]] or trusted.get("actor_ref") != claim["issuer_actor"]:
        raise ValueError("signer role/actor mismatch")
    for k in ("control_ref", "control_version", "resource_ref", "failure_code",
              "evidence_ref", "change_id", "issuer_actor", "nonce"):
        if not isinstance(claim[k], str) or not claim[k].strip():
            raise ValueError("missing " + k)
    if not HEX40.fullmatch(claim["source_revision"]) or not HEX64.fullmatch(claim["evidence_sha256"]):
        raise ValueError("invalid evidence digest or revision")
    if claim["environment"] not in ENV:
        raise ValueError("unsupported environment")
    if not claim["change_id"].startswith("GEN-CHG-"):
        raise ValueError("invalid change ID")
    expected_result = "APPLIED" if claim["kind"] == "DEPLOYMENT" else "PASS"
    if claim["result"] != expected_result:
        raise ValueError("unacceptable proof result")
    effective = instant(claim["at"])
    expires = instant(claim["expires_at"])
    current = instant(now)
    if effective > current or expires <= current or effective >= expires:
        raise ValueError("future or expired claim")
    return claim.copy()

def review_pair(deployment, conformance, keyring, now, *, revoked=(), incident=None):
    deploy = verify_claim(deployment, keyring, now, revoked=revoked)
    check = verify_claim(conformance, keyring, now, revoked=revoked)
    if deploy["kind"] != "DEPLOYMENT" or check["kind"] != "CONFORMANCE":
        raise ValueError("missing deployment and independent conformance")
    if deployment["key_id"] == conformance["key_id"] or deploy["issuer_actor"] == check["issuer_actor"]:
        raise ValueError("same principal cannot self-verify")
    matching = ("control_ref", "control_version", "resource_ref", "source_revision",
                "failure_code", "environment", "change_id")
    if any(deploy[k] != check[k] for k in matching):
        raise ValueError("mismatched scope/version")
    if instant(check["at"]) < instant(deploy["at"]):
        raise ValueError("conformance precedes deployment")
    if deploy["nonce"] == check["nonce"]:
        raise ValueError("reused nonce")
    # Incident evidence is untrusted until separately authenticated by its owner.
    suspected = False
    if incident is not None:
        if not isinstance(incident, dict):
            raise ValueError("invalid incident")
        needed = ("resource_ref", "failure_code", "source_revision", "observed_at")
        if any(not isinstance(incident.get(k), str) for k in needed):
            raise ValueError("incomplete incident")
        same = (incident["resource_ref"] == check["resource_ref"]
                and incident["failure_code"] == check["failure_code"]
                and incident["source_revision"] == check["source_revision"])
        if not same:
            raise ValueError("incident not bound to deployed control revision")
        suspected = instant(incident["observed_at"]) > instant(check["at"])
    return {
        "schema": "genesis.gsc001.control-review/v1",
        "control_ref": deploy["control_ref"], "version": deploy["control_version"],
        "resource_ref": deploy["resource_ref"], "failure_code": deploy["failure_code"],
        "deployment_sha256": sha(deploy), "conformance_sha256": sha(check),
        "review_status": "CRYPTOGRAPHICALLY_CONSISTENT_TEST_PROOFS",
        "independent_institutional_trust": "NOT_ESTABLISHED",
        "external_evidence_custody": "NOT_ESTABLISHED",
        "control_verified_operationally": False,
        "prevention_control_breach": "SUSPECTED_REVIEW_ONLY" if suspected else "NOT_ESTABLISHED",
        "authority": "NO_EXECUTION_GRANT", "execute": False, "deploy": False,
        "merge": False, "promote": False,
    }
