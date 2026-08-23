export type WardenDecision = 'ALLOW' | 'DENY';
export type EffectClass = 'READ' | 'WRITE' | 'EXECUTE' | 'FINANCIAL' | 'PHYSICAL' | 'EXTERNAL_PROVIDER';

export interface WardenDecisionInput {
  decisionReceiptId: string;
  decisionDigest: string;
  decision: WardenDecision;
  principal: { digitalMeId: string; authenticatedPrincipalReceiptId: string };
  action: { actionId: string; capabilityId: string; resourceId: string; effectClass: EffectClass; requestDigest: string; effectBinding?: string };
  authorityRefs?: string[];
  consentRefs?: string[];
  policyRefs: string[];
  grantBinding?: { grantId: string; authorizationTokenDigest: string };
  reasonCodes?: string[];
  issuedAt: string;
  expiresAt: string;
  correlationId?: string;
}

const HEX_64 = /^[A-Fa-f0-9]{64}$/;

export function buildWardenDecisionReceipt(input: WardenDecisionInput) {
  const raw = input as unknown as Record<string, unknown>;
  if ('authorizationToken' in raw || 'authorization_token' in raw) throw new Error('Raw authorization token must not enter Warden decision receipt');
  if (!input.policyRefs?.length) throw new Error('policyRefs are required');
  if (!HEX_64.test(input.action.requestDigest)) throw new Error('requestDigest must be SHA-256 hex');
  if (Date.parse(input.expiresAt) <= Date.parse(input.issuedAt)) throw new Error('expiresAt must be later than issuedAt');
  if (input.decision === 'ALLOW') {
    if (!input.authorityRefs?.length) throw new Error('ALLOW requires authorityRefs');
    if (!input.grantBinding) throw new Error('ALLOW requires grantBinding');
    if (!HEX_64.test(input.grantBinding.authorizationTokenDigest)) throw new Error('authorizationTokenDigest must be SHA-256 hex');
  }
  if (!HEX_64.test(input.decisionDigest)) throw new Error('decisionDigest must be SHA-256 hex');

  return {
    schema_id: 'warden:decision' as const,
    profile_id: 'runtime-exact-action-authorization/v1' as const,
    contract_version: '1.0' as const,
    decision_receipt_id: input.decisionReceiptId,
    decision: input.decision,
    principal_binding: {
      digitalme_id: input.principal.digitalMeId,
      authenticated_principal_receipt_id: input.principal.authenticatedPrincipalReceiptId,
    },
    action_binding: {
      action_id: input.action.actionId,
      capability_id: input.action.capabilityId,
      resource_id: input.action.resourceId,
      effect_class: input.action.effectClass,
      request_digest: input.action.requestDigest.toLowerCase(),
      ...(input.action.effectBinding ? {effect_binding: input.action.effectBinding} : {}),
    },
    ...(input.authorityRefs ? {authority_refs:[...new Set(input.authorityRefs)]} : {}),
    ...(input.consentRefs ? {consent_refs:[...new Set(input.consentRefs)]} : {}),
    policy_refs:[...new Set(input.policyRefs)],
    ...(input.grantBinding ? {grant_binding:{
      grant_id: input.grantBinding.grantId,
      authorization_token_digest: input.grantBinding.authorizationTokenDigest.toLowerCase(),
    }} : {}),
    ...(input.reasonCodes ? {reason_codes:[...new Set(input.reasonCodes)]} : {}),
    issued_at: input.issuedAt,
    expires_at: input.expiresAt,
    ...(input.correlationId ? {correlation_id:input.correlationId} : {}),
    decision_digest: input.decisionDigest.toLowerCase(),
  };
}
