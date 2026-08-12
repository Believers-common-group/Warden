export type WardenDisposition = 'ALLOW' | 'ESCALATE' | 'DENY';

export type CapabilityRule = {
  capability: string;
  disposition: WardenDisposition;
  scopeConstraints?: Record<string, unknown>;
  economicLimits?: Record<string, unknown>;
  delegationConstraints?: Record<string, unknown>;
  reason?: string;
};

export type WardenPolicy = {
  policyId: string;
  version: string;
  validFrom: string;
  validUntil?: string;
  rules: CapabilityRule[];
  defaultDisposition?: Exclude<WardenDisposition, 'ALLOW'>;
};

export type ResolvedPrincipal = {
  organizationId: string;
  principalEntityId: string;
  requesterPrincipalId: string;
  actingCapacity: string;
  active: boolean;
};

export type ResolvedAgentPack = {
  packVersionId: string;
  packCode: string;
  version: string;
  contentHash: string;
  status: 'QUALIFIED' | 'PUBLISHED' | 'SUSPENDED' | 'RETIRED';
  validFrom?: string;
  validUntil?: string;
};

export type AgentIssuanceRequest = {
  requestId: string;
  correlationId: string;
  organizationId: string;
  principalEntityId: string;
  agentIdentityId: string;
  requestedCapabilities: string[];
  purpose: string;
  requestedAt: string;
};

export type IssuanceEvaluationInput = {
  principal: ResolvedPrincipal;
  pack: ResolvedAgentPack;
  request: AgentIssuanceRequest;
  policy: WardenPolicy;
  authorizationDecisionId: string;
  evidenceReference?: string;
  evaluationTime: string;
  modelClaims?: {
    requestedAuthority?: string[];
    runtimeReference?: string;
  };
};

export type CapabilityDecision = {
  capability: string;
  disposition: WardenDisposition;
  reason: string;
};

export type AuthorityEnvelope = {
  organizationId: string;
  principalEntityId: string;
  agentIdentityId: string;
  requestId: string;
  authorizationDecisionId: string;
  allowedCapabilities: string[];
  escalatedCapabilities: string[];
  deniedCapabilities: string[];
  scopeConstraints: Record<string, Record<string, unknown>>;
  economicLimits: Record<string, Record<string, unknown>>;
  delegationConstraints: Record<string, Record<string, unknown>>;
  validFrom: string;
  validUntil?: string;
  policyId: string;
  policyVersion: string;
  packVersionId: string;
  envelopeHash: string;
};

export type AgentIssuance = {
  issuanceId: string;
  organizationId: string;
  principalEntityId: string;
  agentIdentityId: string;
  requestId: string;
  authorityEnvelope: AuthorityEnvelope;
  packVersionId: string;
  authorizationDecisionId: string;
  status: 'ISSUED';
  validFrom: string;
  validUntil?: string;
};

export type IssuanceEvaluationResult = {
  disposition: WardenDisposition;
  decisions: CapabilityDecision[];
  authorityEnvelope?: AuthorityEnvelope;
  issuance?: AgentIssuance;
  reasons: string[];
};
