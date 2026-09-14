import { describe, expect, test } from 'vitest';

import type { EffectReceipt } from '../src/index';

describe('Warden effect receipts', () => {
  test('receipts preserve actor and executor distinction', () => {
    const receipt: EffectReceipt = {
      id: 'receipt:1',
      actionContract: {
        id: 'contract:1',
        actorId: 'digitalme:alice',
        action: 'issue.create',
        resource: 'github:repo:warden',
        input: { title: 'Example' },
      },
      actor: { id: 'digitalme:alice', kind: 'principal' },
      executor: { id: 'door:github', kind: 'service' },
      status: 'succeeded',
      occurredAt: '2026-08-20T00:00:01.000Z',
      evidence: [{ kind: 'github-issue', reference: 'issue:123' }],
    };

    expect(receipt.actor).toEqual({
      id: 'digitalme:alice',
      kind: 'principal',
    });
    expect(receipt.executor).toEqual({ id: 'door:github', kind: 'service' });
    expect(receipt.actor).not.toEqual(receipt.executor);
  });
});
