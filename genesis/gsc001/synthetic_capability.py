"""GSC-001 signed synthetic capability verifier. Never returns operational authority."""
import base64
from datetime import datetime, timezone, timedelta
import json
import re
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

SCHEMA="genesis.gsc001.synthetic-capability/v1"
FIELDS={"schema","kind","key_id","actor_ref","change_id","request_id","audience",
        "resource_ref","source_revision","failure_code","operation","target",
        "before_sha256","after_sha256","nonce","issued_at","expires_at",
        "sandbox_only","execution_domain","advisory_nonce","evidence_ref"}

def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()

def decode(value):
    if not isinstance(value,str) or not re.fullmatch("[A-Za-z0-9_-]+",value):
        raise ValueError("invalid base64url")
    try: decoded=base64.urlsafe_b64decode(value+"="*((-len(value))%4))
    except Exception as exc: raise ValueError("invalid base64url") from exc
    if base64.urlsafe_b64encode(decoded).decode().rstrip("=")!=value:
        raise ValueError("noncanonical base64url")
    return decoded

def instant(value):
    if not isinstance(value,str): raise ValueError("timestamp required")
    try: dt=datetime.fromisoformat(value.replace("Z","+00:00"))
    except ValueError as exc: raise ValueError("invalid timestamp") from exc
    if dt.tzinfo is None: raise ValueError("timezone required")
    return dt.astimezone(timezone.utc)

def verify_synthetic(envelope, pinned_test_keys, as_of, revoked=(), used_nonces=()):
    if not isinstance(envelope,dict) or set(envelope)!={"schema","key_id","payload_b64","signature_b64"}:
        raise ValueError("bad envelope shape")
    if envelope["schema"]!=SCHEMA or envelope["key_id"] not in pinned_test_keys or envelope["key_id"] in revoked:
        raise ValueError("unknown or revoked test signer")
    raw=decode(envelope["payload_b64"])
    sig=decode(envelope["signature_b64"])
    try: Ed25519PublicKey.from_public_bytes(pinned_test_keys[envelope["key_id"]]).verify(sig,raw)
    except Exception as exc: raise ValueError("bad synthetic signature") from exc
    try: payload=json.loads(raw)
    except (UnicodeDecodeError,ValueError) as exc: raise ValueError("bad signed JSON") from exc
    if not isinstance(payload,dict) or set(payload)!=FIELDS or canonical(payload)!=raw:
        raise ValueError("noncanonical capability")
    if any(not isinstance(payload[k],str) or not payload[k].strip() for k in FIELDS-{"sandbox_only"}):
        raise ValueError("missing or mistyped field")
    if (payload["sandbox_only"] is not True or payload["kind"]!="TEST_ONLY_NOT_WARDEN_GRANT"
        or payload["schema"]!=SCHEMA or payload["key_id"]!=envelope["key_id"]):
        raise ValueError("not a synthetic-only capability")
    expected={"execution_domain":"LOCAL_EPHEMERAL_FIXTURE",
              "audience":"SYN_GSC001_TEST_HARNESS",
              "operation":"SIMULATE_REVERSIBLE_COMPATIBILITY_FIX",
              "target":"compatibility.json"}
    if any(payload[k]!=v for k,v in expected.items()) or not payload["actor_ref"].startswith("TEST_ONLY:"):
        raise ValueError("scope outside test harness")
    if payload["nonce"] in used_nonces: raise ValueError("replayed nonce")
    for field in ("before_sha256","after_sha256"):
        if not re.fullmatch("[a-f0-9]{64}",payload[field]):
            raise ValueError("invalid SHA-256")
    if payload["before_sha256"]==payload["after_sha256"]:
        raise ValueError("no test correction")
    issued=instant(payload["issued_at"]); expires=instant(payload["expires_at"]); now=instant(as_of)
    if not issued<=now<expires or expires-issued>timedelta(days=2):
        raise ValueError("test-only capability expired or invalid")
    return payload.copy()
