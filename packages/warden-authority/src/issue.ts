import { createHash } from 'node:crypto';
import { evaluateCapabilities, requestDisposition, validateIssuanceContext } from './evaluate';
import type {
  AuthorityEnvelope,
  IssuanceEvaluationInput,
  IssuanceEvaluationResult,
} from './types';

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, nested]) => `${JSON.stringify(key)}:${stableStringify(nested)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function hashEnvelope(envelope: Omit<AuthorityEnvelope, 'envelopeHash'>): string {
  return createHash('sha256').update(stableStringify(envelope)).digest('hex');
}

function collectRuleMaps(input: IssuanceEvaluationInput, capabilities: string[], key: 'scopeConstraints' | 'economicLimits' | 'delegationConstraints') {
  const result: Record<string, Record<string, unknown>> = {};
  for (const capability of capabilities) {
    const rule = input.policy.rules.find((candidate) => candidate.capability === capability);
    const constraints = rule?.[key];
    if (constraints && Object.keys(constraints).length > 0) result[capability] = constraints;
  }
  return result;
}

export function evaluateIssuanceRequest(input: IssuanceEvaluationInput): IssuanceEvaluationResult {
  const contextFailures = validateIssuanceContext(input);
  if (contextFailures.length > 0) {
    return { disposition: 'DENY', decisions: [], reasons: contextFailures };
  }

  const decisions = evaluateCapabilities(input);
  const disposition = requestDisposition(decisions);
  const allowedCapabilities = decisions.filter((decision) => decision.disposition === 'ALLOW').map((decision) => decision.capability);
  const escalatedCapabilities = decisions.filter((decision) => decision.disposition === 'ESCALATE').map((decision) => decision.capability);
  const deniedCapabilities = decisions.filter((decision) => decision.disposition === 'DENY').map((decision) => decision.capability);

  if (disposition !== 'ALLOW') {
    return {
      disposition,
      decisions,
      reasons: decisions.filter((decision) => decision.disposition !== 'ALLOW').map((decision) => `${decision.capability}:${decision.reason}`),
    };
  }

  const baseEnvelope: Omit<AuthorityEnvelope, 'envelopeHash'> = {
    organizationId: input.request.organizationId,
    principalEntityId: input.request.principalEntityId,
    agentIdentityId: input.request.agentIdentityId,
    requestId: input.request.requestId,
    authorizationDecisionId: input.authorizationDecisionId,
    allowedCapabilities,
    escalatedCapabilities,
    deniedCapabilities,
    scopeConstraints: collectRuleMaps(input, allowedCapabilities, 'scopeConstraints'),
    economicLimits: collectRuleMaps(input, allowedCapabilities, 'economicLimits'),
    delegationConstraints: collectRuleMaps(input, allowedCapabilities, 'delegationConstraints'),
    validFrom: input.evaluationTime,
    validUntil: input.policy.validUntil,
    policyId: input.policy.policyId,
    policyVersion: input.policy.version,
    packVersionId: input.pack.packVersionId,
  };

  const authorityEnvelope: AuthorityEnvelope = {
    ...baseEnvelope,
    envelopeHash: hashEnvelope(baseEnvelope),
  };

  return {
    disposition: 'ALLOW',
    decisions,
    reasons: [],
    authorityEnvelope,
    issuance: {
      issuanceId: `ISS-${input.request.requestId}`,
      organizationId: input.request.organizationId,
      principalEntityId: input.request.principalEntityId,
      agentIdentityId: input.request.agentIdentityId,
      requestId: input.request.requestId,
      authorityEnvelope,
      packVersionId: input.pack.packVersionId,
      authorizationDecisionId: input.authorizationDecisionId,
      status: 'ISSUED',
      validFrom: input.evaluationTime,
      validUntil: input.policy.validUntil,
    },
  };
}
