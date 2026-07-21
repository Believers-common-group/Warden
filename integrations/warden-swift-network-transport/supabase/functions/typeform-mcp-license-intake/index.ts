const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });
}

async function rpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${name}: ${response.status} ${text}`);
  return text ? JSON.parse(text) as T : (null as T);
}

function answerValue(answer: any): unknown {
  switch (answer?.type) {
    case "text": return answer.text ?? "";
    case "email": return answer.email ?? "";
    case "url": return answer.url ?? "";
    case "number": return answer.number ?? null;
    case "boolean": return answer.boolean ?? false;
    case "choice": return answer.choice?.label ?? "";
    case "choices": return answer.choices?.labels ?? [];
    case "phone_number": return answer.phone_number ?? "";
    case "file_url": return answer.file_url ?? "";
    default: return answer?.[answer?.type] ?? null;
  }
}

function normalize(payload: any): Record<string, any> {
  const values: Record<string, any> = {};
  for (const answer of payload?.form_response?.answers ?? []) {
    const ref = answer?.field?.ref;
    if (ref) values[ref] = answerValue(answer);
  }
  const hidden = payload?.form_response?.hidden ?? {};
  const asArray = (value: unknown): string[] => Array.isArray(value) ? value.map(String) : value ? [String(value)] : [];
  return {
    tenant_id: hidden.tenant_id ?? values.tenant_id ?? "",
    organization_id: hidden.organization_id ?? "",
    organization_name: String(values.organization_name ?? ""),
    applicant_name: String(values.applicant_name ?? ""),
    applicant_email: String(values.applicant_email ?? ""),
    applicant_phone: String(values.applicant_phone ?? ""),
    jurisdiction: String(values.jurisdiction ?? ""),
    vsr_licence_ref: String(values.vsr_licence_ref ?? hidden.vsr_licence_ref ?? ""),
    current_vsr_licence_type: String(values.current_vsr_licence_type ?? ""),
    requested_licence_tier: String(values.requested_licence_tier ?? "sandbox"),
    connector_name: String(values.connector_name ?? ""),
    provider_name: String(values.provider_name ?? ""),
    repository_url: String(values.repository_url ?? ""),
    manifest_url: String(values.manifest_url ?? ""),
    documentation_url: String(values.documentation_url ?? ""),
    transport_modes: asArray(values.transport_modes),
    deployment_model: String(values.deployment_model ?? ""),
    target_vsr_licences: asArray(values.target_vsr_licences),
    requested_operations: asArray(values.requested_operations),
    data_classes: asArray(values.data_classes),
    auth_methods: asArray(values.auth_methods),
    data_residency: String(values.data_residency ?? ""),
    retention_days: values.retention_days ?? null,
    sandbox_endpoint: String(values.sandbox_endpoint ?? ""),
    production_endpoint: String(values.production_endpoint ?? ""),
    privacy_policy_url: String(values.privacy_policy_url ?? ""),
    security_document_url: String(values.security_document ?? ""),
    support_contact: String(values.support_contact ?? ""),
    capabilities: {
      tools_count: values.tools_count ?? 0,
      resources_count: values.resources_count ?? 0,
      prompts_count: values.prompts_count ?? 0,
      description: String(values.capabilities_description ?? ""),
      destructive_actions: Boolean(values.destructive_actions ?? false),
      human_approval: Boolean(values.human_approval ?? false),
      riveros_evidence: Boolean(values.riveros_evidence ?? false),
      warden_policy_enforcement: Boolean(values.warden_policy_enforcement ?? false),
    },
  };
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!SUPABASE_URL || !SERVICE_KEY) return json(503, { error: "service_not_configured" });
  const signature = request.headers.get("typeform-signature") ?? "";
  const rawBody = await request.text();
  let payload: any;
  try { payload = JSON.parse(rawBody); } catch { return json(400, { error: "invalid_json" }); }
  try {
    const valid = await rpc<boolean>("warden_verify_typeform_signature", { p_raw_body: rawBody, p_signature: signature });
    if (!valid) return json(403, { error: "invalid_typeform_signature" });
    const normalized = normalize(payload);
    const required = ["organization_name", "applicant_name", "applicant_email", "vsr_licence_ref", "requested_licence_tier", "connector_name", "provider_name"];
    const missing = required.filter((key) => !normalized[key]);
    if (missing.length > 0) return json(422, { error: "missing_required_answers", fields: missing });
    const result = await rpc<any>("warden_record_typeform_mcp_submission", {
      p_raw_payload: payload,
      p_normalized_payload: normalized,
      p_signature: signature,
    });
    return json(200, result);
  } catch (error) {
    console.error("typeform intake failure", error);
    return json(503, { error: "intake_unavailable" });
  }
});
