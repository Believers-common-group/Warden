import { allow, deny, type ActionContract } from '@warden/core';
import type { EvidenceReservation } from '@warden/river';
import { describe, expect, expectTypeOf, it } from 'vitest';

import {
  MULTISTREAM_ACTIONS,
  runGovernedAction,
  type GovernedPathDependencies,
  type MultiStreamAction,
  type MultiStreamIntent,
} from '../src/index.js';

interface ContactInput {
  message: string;
}

const clock = () => '2026-08-28T10:00:00.000Z';

describe('Multi-Stream Alpha contract', () => {
  it('exports closed typed action identifiers for every required family', () => {
    for (const family of [
      'CONTACT',
      'CONVERSATION',
      'EVENT',
      'INBOX',
      'COMMUNITY',
      'CHANNEL',
      'MODERATION',
    ]) {
      expect(
        MULTISTREAM_ACTIONS.some((action) =>
          action.startsWith(`MULTISTREAM.${family}.`),
        ),
      ).toBe(true);
    }
    expectTypeOf<MultiStreamAction>().toMatchTypeOf<string>();
  });

  it('records denial after event resolution without Door execution or admission', async () => {
    const trace: string[] = [];
    const river: EvidenceReservation[] = [];
    const intent: MultiStreamIntent = {
      id: 'intent:event:1',
      actorId: 'digitalme:alice',
      action: 'MULTISTREAM.EVENT.ADMIT',
      resource: 'event:valid-address',
      input: { eventAddress: 'event:valid-address' },
    };
    const dependencies: GovernedPathDependencies<unknown, unknown> = {
      compileContext: async () => {
        trace.push('context:resolved');
        return {
          id: 'context:1',
          intentId: intent.id,
          resource: intent.resource,
          resolved: true,
          provenance: ['registry:event:valid-address'],
          compiledAt: clock(),
        };
      },
      decide: async () => {
        trace.push('warden:deny');
        return deny('EVENT_ADMISSION_NOT_AUTHORIZED');
      },
      recordRiver: async (record) => {
        trace.push(`river:${record.status}`);
        river.push(record);
      },
      execute: async () => {
        trace.push('door:executed');
        throw new Error('Door must not execute');
      },
      observe: async () => {
        throw new Error('Admission must not be observed');
      },
      verify: async () => {
        throw new Error('Admission must not be verified');
      },
      project: async () => {
        trace.push('admission:written');
      },
      now: clock,
      id: () => 'river:denial:1',
      workQueueBinding: () => 'work:event:1',
    };

    const result = await runGovernedAction(intent, dependencies);

    expect(result.outcome).toBe('denied');
    expect(trace).toEqual(['context:resolved', 'warden:deny', 'river:denied']);
    expect(river[0]).toMatchObject({
      status: 'denied',
      decisionReason: 'EVENT_ADMISSION_NOT_AUTHORIZED',
      workQueueBinding: 'work:event:1',
    });
    expect(river[0]).not.toHaveProperty('actionContract');
  });

  it('delivers an allowed ContactIntent and projects Inbox only after verification', async () => {
    const trace: string[] = [];
    const intent: MultiStreamIntent<ContactInput> = {
      id: 'intent:contact:1',
      actorId: 'digitalme:alice',
      action: 'MULTISTREAM.CONTACT.DELIVER',
      resource: 'contact:bob',
      input: { message: 'Hello' },
    };
    const contract: ActionContract<ContactInput> = {
      id: 'contract:contact:1',
      actorId: intent.actorId,
      action: intent.action,
      resource: intent.resource,
      input: intent.input,
    };
    const dependencies: GovernedPathDependencies<
      ContactInput,
      { deliveryId: string }
    > = {
      compileContext: async () => {
        trace.push('context:receipt');
        return {
          id: 'context:contact:1',
          intentId: intent.id,
          resource: intent.resource,
          resolved: true,
          provenance: ['contact-registry:bob'],
          compiledAt: clock(),
        };
      },
      decide: async () => {
        trace.push('warden:allow');
        return allow(contract, 'authority:contact:deliver');
      },
      recordRiver: async (record) => {
        trace.push(`river:${record.status}`);
      },
      execute: async () => {
        trace.push('adapter:executed');
        return { deliveryId: 'delivery:1' };
      },
      observe: async (_action, output) => {
        trace.push('delivery:observed');
        return {
          output,
          evidence: [
            { kind: 'provider-delivery', reference: output.deliveryId },
          ],
        };
      },
      verify: async () => {
        trace.push('effect:verified');
        return {
          status: 'verified',
          observedAt: clock(),
          evidence: [{ kind: 'provider-delivery', reference: 'delivery:1' }],
        };
      },
      project: async () => {
        trace.push('inbox:projected');
      },
      now: clock,
      id: () => 'river:reservation:1',
      workQueueBinding: () => 'work:contact:1',
    };

    const result = await runGovernedAction(intent, dependencies);

    expect(result.outcome).toBe('completed');
    expect(trace).toEqual([
      'context:receipt',
      'warden:allow',
      'river:reserved',
      'adapter:executed',
      'delivery:observed',
      'effect:verified',
      'river:sealed',
      'inbox:projected',
    ]);
  });
});
