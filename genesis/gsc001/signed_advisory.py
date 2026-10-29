"""GSC-001 offline Ed25519 advisory verifier. Not an executable Warden grant."""
import base64
from datetime import datetime, timezone
import json
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization

def decode(value):
    if not isinstance(value, str) or not value or any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_' for c in value):
        raise ValueError('noncanonical base64url')
    raw=base64.urlsafe_b64decode(value+'='*((-len(value))%4))
    if base64.urlsafe_b64encode(raw).decode().rstrip('=') != value:
        raise ValueError('noncanonical base64url')
    return raw

def instant(value):
    if not isinstance(value,str): raise ValueError('timestamp required')
    try: dt=datetime.fromisoformat(value.replace('Z','+00:00'))
    except ValueError as exc: raise ValueError('invalid timestamp') from exc
    if dt.tzinfo is None: raise ValueError('timezone required')
    return dt.astimezone(timezone.utc)

def canonical(obj):
    return json.dumps(obj,sort_keys=True,separators=(',', ':'),ensure_ascii=True).encode()

def verify(envelope, keys, now, expected_audience, revoked=(), used_nonces=()):
    if not isinstance(envelope,dict) or set(envelope)!={'schema','key_id','payload_b64','signature_b64'}:
        raise ValueError('invalid envelope fields')
    if envelope['schema']!='genesis.gsc001.signed-advisory/v1':
        raise ValueError('unsupported envelope schema')
    key_id=envelope['key_id']
    if not isinstance(key_id,str) or key_id not in keys or key_id in revoked:
        raise ValueError('untrusted or revoked signing key')
    raw=decode(envelope['payload_b64'])
    signature=decode(envelope['signature_b64'])
    public=serialization.load_pem_public_key(keys[key_id].encode())
    try: public.verify(signature,raw)
    except (InvalidSignature, ValueError) as exc: raise ValueError('invalid signature') from exc
    try: payload=json.loads(raw.decode('utf-8'))
    except (ValueError,UnicodeDecodeError) as exc: raise ValueError('invalid payload json') from exc
    if not isinstance(payload,dict) or raw!=canonical(payload):
        raise ValueError('noncanonical payload')
    required={'action','actor_ref','audience','authority','change_id','environment','evidence_ref','expires_at','failure_code','issued_at','may_execute','nonce','request_id','resource_ref','severity','source_revision','status'}
    if set(payload)!=required or any(not isinstance(payload[k],str) or not payload[k].strip() for k in required-{'may_execute'}):
        raise ValueError('invalid advisory fields')
    if payload['action']!='propose_repair' or payload['authority']!='NONE' or payload['may_execute'] is not False or payload['status']!='REVIEW_REQUIRED':
        raise ValueError('advisory cannot grant execution authority')
    if payload['audience']!=expected_audience:
        raise ValueError('audience mismatch')
    if payload['nonce'] in used_nonces:
        raise ValueError('replayed nonce')
    if payload['severity'] not in {'S2','S3','S4'} or payload['environment'] not in {'development','local','staging'}:
        raise ValueError('unexpected severity or environment')
    issued=instant(payload['issued_at']); expiry=instant(payload['expires_at']); current=instant(now)
    if current < issued or current >= expiry or expiry <= issued:
        raise ValueError('advisory expired or not yet valid')
    return payload.copy()
