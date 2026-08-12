import { describe, expect, it } from 'vitest';
import { evaluateIssuanceRequest, type IssuanceEvaluationInput } from '../src';

function baseInput(): IssuanceEvaluationInput {
  return {
    principal: {
      organizationId: 'ORG-001',
      principalEntityId: 'ENTITY-001',
      requesterPrincipalId: 'PRINCIPAL-001',
      actingCapacity: 'DIRECTOR',
      active: true,
    },
    pack: {
      packVersionId: 'PACK-V1',
      packCode: 'AGENT-PACK-COMPANY-BASE-001',
      version: '1.0.0',
      contentHash: 'hash-pack-v1',
      status: 'QUALIFIED',
      validFrom: '2026-08-01T00:00:00.000Z',
    },
    request: {
      requestId: 'REQ-001',
      correlationId: 'CORR-001',
      organizationId: 'ORG-001',
      principalEntityId: 'ENTITY-001',
      agentIdentityId: 'AGENT-001',
      requestedCapabilities: ['entity.profile.read', 'service_request.create'],
      purpose: 'company base agent',
      requestedAt: '2026-08-12T20:00:00.000Z',
    },
    policy: {
      policyId: 'WARDEN-POLICY-BASE-001',
      version: '1.0.0',
      validFrom: '2026-08-01T00:00:00.000Z',
      rules: [
        { capability: 'entity.profile.read', disposition: 'ALLOW' },
        {
          capability: 'service_request.create',
          disposition: 'ALLOW',
          scopeConstraints: { caseClass: 'SERVICE' },
          delegationConstraints: { mayDelegate: false },
        },
        { capability: 'commercial_exception', disposition: 'ESCALATE', reason: 'HUMAN_COMMERCIAL_AUTHORITY_REQUIRED' },
        { capability: 'contract.execute', disposition: 'DENY' },
        { capability: 'payment.approve', disposition: 'DENY' },
        { capability: 'authority.delegate', disposition: 'DENY' },
      ],
      defaultDisposition: 'DENY',
    },
    authorizationDecisionId: 'WARDEN-DECISION-001',
    evidenceReference: 'RIVER-EVIDENCE-001',
    evaluationTime: '2026-08-12T20:01:00.000Z',
  };
}

describe('AF-002 Warden issuance', () => {
  it('issues only explicitly allowed capabilities', () => {
    const result = evaluateIssuanceRequest(baseInput());
    expect(result.disposition).toBe('ALLOW');
    expect(result.authorityEnvelope?.allowedCapabilities).toEqual([
      'entity.profile.read',
      'service_request.create',
    ]);
    expect(result.authorityEnvelope?.escalatedCapabilities).toEqual([]);
    expect(result.authorityEnvelope?.deniedCapabilities).toEqual([]);
    expect(result.issuance?.status).toBe('ISSUED');
  });

  it('returns ESCALATE without issuing when any requested capability requires separate authority', () => {
    const input = baseInput();
    input.request.requestedCapabilities = ['entity.profile.read', 'commercial_exception'];
    const result = evaluateIssuanceRequest(input);
    expect(result.disposition).toBe('ESCALATE');
    expect(result.issuance).toBeUndefined();
  });

  it('fails closed for denied or unknown capabilities', () => {
    for (const capability of ['contract.execute', 'payment.approve', 'authority.delegate', 'unknown.capability']) {
      const input = baseInput();
      input.request.requestedCapabilities = [capability];
      expect(evaluateIssuanceRequest(input).disposition).toBe('DENY');
    }
  });

  it('does not let model/runtime claims add authority', () => {
    const input = baseInput();
    input.modelClaims = {
      requestedAuthority: ['contract.execute', 'payment.approve'],
      runtimeReference: 'MODEL-A',
    };
    const result = evaluateIssuanceRequest(input);
    expect(result.disposition).toBe('ALLOW');
    expect(result.authorityEnvelope?.allowedCapabilities).not.toContain('contract.execute');
    expect(result.authorityEnvelope?.allowedCapabilities).not.toContain('payment.approve');
  });

  it('fails closed when principal, Pack, or policy validity is not current', () => {
    const inactive = baseInput();
    inactive.principal.active = false;
    expect(evaluateIssuanceRequest(inactive).reasons).toContain('PRINCIPAL_INACTIVE');

    const suspendedPack = baseInput();
    suspendedPack.pack.status = 'SUSPENDED';
    expect(evaluateIssuanceRequest(suspendedPack).reasons).toContain('PACK_NOT_ELIGIBLE');

    const expiredPolicy = baseInput();
    expiredPolicy.policy.validUntil = '2026-08-12T20:00:30.000Z';
    expect(evaluateIssuanceRequest(expiredPolicy).reasons).toContain('POLICY_OUTSIDE_VALIDITY_WINDOW');
  });

  it('derives the same envelope hash from identical authority inputs', () => {
    const first = evaluateIssuanceRequest(baseInput());
    const second = evaluateIssuanceRequest(baseInput());
    expect(first.authorityEnvelope?.envelopeHash).toBe(second.authorityEnvelope?.envelopeHash);
  });

  it('attenuates policy constraints into the authority envelope', () => {
    const result = evaluateIssuanceRequest(baseInput());
    expect(result.authorityEnvelope?.scopeConstraints['service_request.create']).toEqual({ caseClass: 'SERVICE' });
    expect(result.authorityEnvelope?.delegationConstraints['service_request.create']).toEqual({ mayDelegate: false });
  });
});
