import type { ActionContract } from '@warden/core';

/** A party involved in requesting or executing an effect. */
export interface ReceiptParty {
  id: string;
  kind: 'principal' | 'agent' | 'service';
}

/** Evidence produced by execution and suitable for later RiverOS storage. */
export interface EffectEvidence {
  kind: string;
  reference: string;
  digest?: string;
}

/** A durable account of an attempted effect. */
export interface EffectReceipt<TInput = unknown, TOutput = unknown> {
  id: string;
  actionContract: ActionContract<TInput>;
  actor: ReceiptParty;
  executor: ReceiptParty;
  status: 'succeeded' | 'failed';
  occurredAt: string;
  output?: TOutput;
  evidence: readonly EffectEvidence[];
}

/** Evidence reserved before a governed executor is allowed to mutate state. */
export interface EvidenceReservation<TInput = unknown> {
  id: string;
  actionContract?: ActionContract<TInput>;
  requestedAction?: {
    actorId: string;
    action: string;
    resource: string;
    input: TInput;
  };
  status: 'reserved' | 'denied' | 'sealed' | 'exception';
  recordedAt: string;
  decisionReason?: string;
  workQueueBinding?: string;
}

/** The observation used to prove that a requested effect actually occurred. */
export interface EffectVerification {
  status: 'verified' | 'unverified';
  observedAt: string;
  evidence: readonly EffectEvidence[];
  exceptionCode?: string;
}
