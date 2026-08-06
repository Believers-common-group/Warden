const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RECEIPT_KEY_ID = "riveros-supabase-hmac-v1";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type WardenEvent = Record<string, any>;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function canonicalize(value: any): any {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((acc: Record<string, any>, key) => {
      acc[key] = canonicalize(value[key]);
      return acc;
    }, {});
  }
  return value;
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function hexToBytes(hex: string): Uint8Array {
  if (!/^[0-9a-f]{64}$/i.test(hex)) throw new Error("invalid hash");
  return new Uint8Array(hex.match(/.{2}/g)!.map((value) => parseInt(value, 16)));
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function rpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${name}: ${response.status} ${text}`);
  return text ? JSON.parse(text) as T : (null as T);
}

async function verifyEd25519(events: WardenEvent[], publicKeyB64: string, keyID: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    base64ToBytes(publicKeyB64),
    { name: "Ed25519" },
    false,
    ["verify"],
  );
  for (const event of events) {
    if (event.signature?.algorithm !== "ed25519-sha256-digest" || event.signature?.keyID !== keyID) return false;
    const valid = await crypto.subtle.verify(
      { name: "Ed25519" },
      key,
      base64ToBytes(event.signature.value),
      hexToBytes(event.eventHash),
    );
    if (!valid) return false;
  }
  return true;
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!SUPABASE_URL || !SERVICE_KEY) return json(503, { error: "service_not_configured" });

  const tenantID = request.headers.get("x-warden-tenant-id") ?? "";
  const deviceID = request.headers.get("x-warden-device-id") ?? "";
  const headerBatchID = request.headers.get("x-warden-batch-id") ?? "";
  const idempotencyKey = request.headers.get("idempotency-key") ?? "";
  const apiKey = request.headers.get("x-api-key") ?? "";

  let envelope: any;
  try { envelope = JSON.parse(await request.text()); }
  catch { return json(400, { error: "invalid_json" }); }

  const events: WardenEvent[] = Array.isArray(envelope?.events) ? envelope.events : [];
  if (!tenantID || !deviceID || !headerBatchID || !apiKey || events.length === 0) {
    return json(400, { error: "missing_protocol_fields" });
  }
  if (envelope.batchID !== headerBatchID || idempotencyKey !== headerBatchID || envelope.tenantID !== tenantID) {
    return json(409, { error: "batch_identity_mismatch" });
  }

  const material = `${tenantID}\n${deviceID}\n${events.map((event) => event.id).join("\n")}`;
  const expectedBatchID = `batch-${await sha256Hex(new TextEncoder().encode(material))}`;
  if (expectedBatchID !== headerBatchID) return json(409, { error: "invalid_batch_id" });

  const eventIDs = new Set<string>();
  for (const event of events) {
    if (!event?.id || eventIDs.has(event.id)) return json(400, { error: "duplicate_or_missing_event_id" });
    eventIDs.add(event.id);
    if (event.tenantID !== tenantID || event.deviceID !== deviceID) return json(409, { error: "mixed_event_identity" });
    const unsigned = { ...event };
    delete unsigned.eventHash;
    delete unsigned.signature;
    const expectedHash = await sha256Hex(new TextEncoder().encode(canonicalJson(unsigned)));
    if (expectedHash !== event.eventHash) return json(422, { error: "event_hash_mismatch", eventID: event.id });
  }

  try {
    const tenant = await rpc<any>("warden_validate_tenant_api_key", {
      p_external_tenant_id: tenantID,
      p_api_key: apiKey,
    });
    if (!tenant?.ok) return json(401, { error: tenant?.code ?? "tenant_auth_failed" });

    const device = await rpc<any>("warden_get_device", {
      p_external_tenant_id: tenantID,
      p_external_device_id: deviceID,
    });
    if (!device?.ok) return json(403, { error: device?.code ?? "device_not_authorized" });
    if (events.some((event) => event.projectID !== device.projectID)) return json(403, { error: "project_not_authorized" });

    if (device.algorithm === "hmac-sha256") {
      const verification = await rpc<any>("warden_verify_device_hmac_batch", {
        p_external_tenant_id: tenantID,
        p_external_device_id: deviceID,
        p_events: events,
      });
      if (!verification?.ok) return json(403, { error: verification?.code ?? "signature_failed", eventID: verification?.eventID });
    } else if (device.algorithm === "ed25519-sha256-digest") {
      if (!device.verificationKeyB64 || !(await verifyEd25519(events, device.verificationKeyB64, device.keyID))) {
        return json(403, { error: "invalid_event_signature" });
      }
    } else {
      return json(422, { error: "unsupported_signature_algorithm" });
    }

    const acknowledgement = await rpc<any>("warden_commit_batch", {
      p_batch_id: headerBatchID,
      p_external_tenant_id: tenantID,
      p_external_device_id: deviceID,
      p_events: events,
    });

    const accepted = Array.isArray(acknowledgement.accepted) ? acknowledgement.accepted : [];
    if (accepted.length > 0) {
      const canonicalClaims = accepted.map((receipt: Record<string, Json>) => canonicalJson(receipt));
      const signatures = await rpc<string[]>("warden_sign_receipts", { p_canonical_claims: canonicalClaims });
      acknowledgement.accepted = accepted.map((receipt: Record<string, Json>, index: number) => ({
        ...receipt,
        serverSignature: {
          algorithm: "hmac-sha256-v2",
          keyID: RECEIPT_KEY_ID,
          value: signatures[index],
        },
      }));
    }
    return json(200, acknowledgement);
  } catch (error) {
    console.error("warden-ingest failure", error);
    return json(503, { error: "ingestion_unavailable" });
  }
});
