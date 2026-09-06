import { describe, expect, test } from 'vitest';
import {
  validateActionDecision,
  validateDelegatedToolLease,
  validateSignalBaton,
  validateToolLease,
  type ActionRequestBinding,
  type SignalBaton,
  type ToolLease,
  type WardenDecisionReceipt,
} from '../../src/extensions/wardenTransactionRuntime';

const NOW = new Date('2026-09-06T12:15:00Z');

const request: ActionRequestBinding = {
  podId: 'POD-SCOTTS-20260906-000001',
  digitalMeId: 'DM-OPERATOR-0042',
  authenticatedPrincipalReceiptId: 'APR-SCOTTS-0042',
  actionId: 'COMPLETE_PRODUCTION',
  capabilityId: 'production.complete',
  resourceId: 'GARMENT-BATCH-8821',
  requestDigest: '1'.repeat(64),
  locationId: 'LOC-SCOTTS-DBP-001',
  quantity: 840,
  unit: 'PCS',
};

const decision: WardenDecisionReceipt = {
  decisionReceiptId: 'WD-20260906-82101',
  decision: 'ALLOW',
  digitalMeId: request.digitalMeId,
  authenticatedPrincipalReceiptId: request.authenticatedPrincipalReceiptId,
  actionId: request.actionId,
  capabilityId: request.capabilityId,
  resourceId: request.resourceId,
  requestDigest: request.requestDigest,
  expiresAt: '2026-09-06T12:30:00Z',
};

const lease: ToolLease = {
  leaseId: 'TL-8821-001',
  principalId: request.digitalMeId,
  wardenDecisionId: decision.decisionReceiptId,
  capabilityId: request.capabilityId,
  targetId: request.resourceId,
  actionId: request.actionId,
  locationId: request.locationId,
  maxQuantity: 840,
  unit: 'PCS',
  expiresAt: '2026-09-06T12:30:00Z',
  integrityRef: '2'.repeat(64),
};

const baton: SignalBaton = {
  batonId: 'BATON-8821-001',
  podId: request.podId,
  wardenDecisionRef: decision.decisionReceiptId,
  toolLeaseRef: lease.leaseId,
  idempotencyKey: 'IDEM-POD-SCOTTS-20260906-000001',
  expiresAt: '2026-09-06T12:30:00Z',
  integrityRef: '3'.repeat(64),
};

describe('validateActionDecision', () => {
  test('allows only an exact fresh decision binding', () => {
    expect(validateActionDecision(request, decision, NOW)).toEqual({ allowed: true, code: 'ALLOW' });
  });

  test.each([
    ['digitalMeId', 'DM-OTHER-001'],
    ['capabilityId', 'production.override'],
    ['resourceId', 'GARMENT-BATCH-OTHER'],
    ['requestDigest', 'f'.repeat(64)],
  ] as const)('fails closed when %s differs', (field, value) => {
    const changed = { ...decision, [field]: value };
    expect(validateActionDecision(request, changed, NOW)).toEqual({ allowed: false, code: 'WARDEN_SCOPE_MISMATCH' });
  });

  test('fails closed on DENY or expiry', () => {
    expect(validateActionDecision(request, { ...decision, decision: 'DENY' }, NOW).code).toBe('WARDEN_NOT_ALLOWED');
    expect(validateActionDecision(request, { ...decision, expiresAt: '2026-09-06T12:14:59Z' }, NOW).code).toBe('WARDEN_EXPIRED');
  });
});

describe('validateToolLease', () => {
  test('accepts an exact bounded lease', () => {
    expect(validateToolLease(request, decision, lease, NOW)).toEqual({ allowed: true, code: 'ALLOW' });
  });

  test('rejects expiry, target mismatch, or quantity expansion', () => {
    expect(validateToolLease(request, decision, { ...lease, expiresAt: '2026-09-06T12:14:59Z' }, NOW).code).toBe('TOOLLEASE_EXPIRED');
    expect(validateToolLease(request, decision, { ...lease, targetId: 'OTHER' }, NOW).code).toBe('TOOLLEASE_SCOPE_MISMATCH');
    expect(validateToolLease(request, decision, { ...lease, maxQuantity: 839 }, NOW).code).toBe('TOOLLEASE_SCOPE_MISMATCH');
  });
});

describe('validateDelegatedToolLease', () => {
  test('allows an equal or smaller child scope and rejects expansion', () => {
    expect(validateDelegatedToolLease(lease, { ...lease, leaseId: 'TL-CHILD', maxQuantity: 400 }).code).toBe('ALLOW');
    expect(validateDelegatedToolLease(lease, { ...lease, leaseId: 'TL-CHILD', maxQuantity: 841 }).code).toBe('DELEGATED_SCOPE_EXCEEDED');
    expect(validateDelegatedToolLease(lease, { ...lease, leaseId: 'TL-CHILD', targetId: 'OTHER' }).code).toBe('DELEGATED_SCOPE_EXCEEDED');
  });
});

describe('validateSignalBaton', () => {
  test('accepts only exact references with fresh expiry and integrity', () => {
    expect(validateSignalBaton(baton, request, decision, lease, NOW)).toEqual({ allowed: true, code: 'ALLOW' });
    expect(validateSignalBaton({ ...baton, toolLeaseRef: 'TL-OTHER' }, request, decision, lease, NOW).code).toBe('BATON_BINDING_MISMATCH');
    expect(validateSignalBaton({ ...baton, expiresAt: '2026-09-06T12:14:59Z' }, request, decision, lease, NOW).code).toBe('BATON_EXPIRED');
    expect(validateSignalBaton({ ...baton, integrityRef: 'not-a-digest' }, request, decision, lease, NOW).code).toBe('BATON_INTEGRITY_INVALID');
  });
});
