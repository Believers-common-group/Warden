import type {
  CapabilityDecision,
  CapabilityRule,
  IssuanceEvaluationInput,
  WardenDisposition,
} from './types';

function inWindow(now: Date, from?: string, until?: string): boolean {
  if (from && now < new Date(from)) return false;
  if (until && now >= new Date(until)) return false;
  return true;
}

function findRule(rules: CapabilityRule[], capability: string): CapabilityRule | undefined {
  return rules.find((rule) => rule.capability === capability);
}

export function validateIssuanceContext(input: IssuanceEvaluationInput): string[] {
  const reasons: string[] = [];
  const now = new Date(input.evaluationTime);

  if (!input.principal.active) reasons.push('PRINCIPAL_INACTIVE');
  if (input.principal.organizationId !== input.request.organizationId) reasons.push('ORGANIZATION_MISMATCH');
  if (input.principal.principalEntityId !== input.request.principalEntityId) reasons.push('PRINCIPAL_ENTITY_MISMATCH');
  if (!['QUALIFIED', 'PUBLISHED'].includes(input.pack.status)) reasons.push('PACK_NOT_ELIGIBLE');
  if (!inWindow(now, input.pack.validFrom, input.pack.validUntil)) reasons.push('PACK_OUTSIDE_VALIDITY_WINDOW');
  if (!inWindow(now, input.policy.validFrom, input.policy.validUntil)) reasons.push('POLICY_OUTSIDE_VALIDITY_WINDOW');
  if (new Date(input.request.requestedAt) > now) reasons.push('REQUEST_FROM_FUTURE');
  if (!input.authorizationDecisionId) reasons.push('AUTHORIZATION_DECISION_REQUIRED');

  return reasons;
}

export function evaluateCapabilities(input: IssuanceEvaluationInput): CapabilityDecision[] {
  const fallback: WardenDisposition = input.policy.defaultDisposition ?? 'DENY';
  return [...new Set(input.request.requestedCapabilities)].sort().map((capability) => {
    const rule = findRule(input.policy.rules, capability);
    const disposition = rule?.disposition ?? fallback;
    return {
      capability,
      disposition,
      reason: rule?.reason ?? (rule ? `POLICY_${disposition}` : 'NO_MATCHING_POLICY_RULE'),
    };
  });
}

export function requestDisposition(decisions: CapabilityDecision[]): WardenDisposition {
  if (decisions.some((decision) => decision.disposition === 'DENY')) return 'DENY';
  if (decisions.some((decision) => decision.disposition === 'ESCALATE')) return 'ESCALATE';
  return 'ALLOW';
}
