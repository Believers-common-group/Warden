import type { ActionContract, DecisionResult } from '@warden/core';
import type {
  EffectEvidence,
  EffectVerification,
  EvidenceReservation,
} from '@warden/river';

export const MULTISTREAM_ACTIONS = [
  'MULTISTREAM.CONTACT.DELIVER',
  'MULTISTREAM.CONTACT.BLOCK',
  'MULTISTREAM.CONVERSATION.CREATE',
  'MULTISTREAM.CONVERSATION.REPLY',
  'MULTISTREAM.EVENT.ADMIT',
  'MULTISTREAM.EVENT.RSVP',
  'MULTISTREAM.INBOX.ACKNOWLEDGE',
  'MULTISTREAM.INBOX.ARCHIVE',
  'MULTISTREAM.COMMUNITY.JOIN',
  'MULTISTREAM.COMMUNITY.LEAVE',
  'MULTISTREAM.CHANNEL.PUBLISH',
  'MULTISTREAM.CHANNEL.SUBSCRIBE',
  'MULTISTREAM.MODERATION.REVIEW',
  'MULTISTREAM.MODERATION.ENFORCE',
] as const;

export type MultiStreamAction = (typeof MULTISTREAM_ACTIONS)[number];

export interface MultiStreamIntent<TInput = unknown> {
  id: string;
  actorId: string;
  action: MultiStreamAction;
  resource: string;
  input: TInput;
}

export interface ContextReceipt {
  id: string;
  intentId: string;
  resource: string;
  resolved: boolean;
  provenance: readonly string[];
  compiledAt: string;
}

export type ExceptionTaxonomy =
  | 'EXECUTION_FAILED'
  | 'OBSERVATION_FAILED'
  | 'EFFECT_UNVERIFIED'
  | 'PROJECTION_FAILED';

export interface ExecutionObservation<TOutput = unknown> {
  output: TOutput;
  evidence: readonly EffectEvidence[];
}

export interface GovernedPathDependencies<TInput, TOutput> {
  compileContext(intent: MultiStreamIntent<TInput>): Promise<ContextReceipt>;
  decide(
    intent: MultiStreamIntent<TInput>,
    context: ContextReceipt,
  ): Promise<DecisionResult<TInput>>;
  recordRiver(record: EvidenceReservation<TInput>): Promise<void>;
  execute(
    contract: ActionContract<TInput>,
    reservation: EvidenceReservation<TInput>,
  ): Promise<TOutput>;
  observe(
    contract: ActionContract<TInput>,
    output: TOutput,
  ): Promise<ExecutionObservation<TOutput>>;
  verify(
    contract: ActionContract<TInput>,
    observation: ExecutionObservation<TOutput>,
  ): Promise<EffectVerification>;
  project(
    contract: ActionContract<TInput>,
    observation: ExecutionObservation<TOutput>,
  ): Promise<void>;
  now(): string;
  id(): string;
  workQueueBinding(intent: MultiStreamIntent<TInput>): string;
}

export type GovernedPathResult<TInput, TOutput> =
  | {
      outcome: 'denied';
      context: ContextReceipt;
      river: EvidenceReservation<TInput>;
    }
  | {
      outcome: 'completed';
      context: ContextReceipt;
      river: EvidenceReservation<TInput>;
      observation: ExecutionObservation<TOutput>;
      verification: EffectVerification;
    }
  | {
      outcome: 'exception';
      context: ContextReceipt;
      river: EvidenceReservation<TInput>;
      exception: ExceptionTaxonomy;
    };

/** Runs a Multi-Stream intent through Alpha's existing governed action path. */
export async function runGovernedAction<TInput, TOutput>(
  intent: MultiStreamIntent<TInput>,
  dependencies: GovernedPathDependencies<TInput, TOutput>,
): Promise<GovernedPathResult<TInput, TOutput>> {
  const context = await dependencies.compileContext(intent);
  const decision = await dependencies.decide(intent, context);
  const common = {
    id: dependencies.id(),
    recordedAt: dependencies.now(),
    workQueueBinding: dependencies.workQueueBinding(intent),
  };

  if (decision.outcome === 'deny') {
    const river: EvidenceReservation<TInput> = {
      ...common,
      requestedAction: {
        actorId: intent.actorId,
        action: intent.action,
        resource: intent.resource,
        input: intent.input,
      },
      status: 'denied',
      decisionReason: decision.reason,
    };
    await dependencies.recordRiver(river);
    return { outcome: 'denied', context, river };
  }

  const river: EvidenceReservation<TInput> = {
    ...common,
    actionContract: decision.actionContract,
    status: 'reserved',
  };
  await dependencies.recordRiver(river);

  const fail = async (
    exception: ExceptionTaxonomy,
  ): Promise<GovernedPathResult<TInput, TOutput>> => {
    const exceptionRiver = { ...river, status: 'exception' as const };
    await dependencies.recordRiver(exceptionRiver);
    return { outcome: 'exception', context, river: exceptionRiver, exception };
  };

  let output: TOutput;
  try {
    output = await dependencies.execute(decision.actionContract, river);
  } catch {
    return fail('EXECUTION_FAILED');
  }

  let observation: ExecutionObservation<TOutput>;
  try {
    observation = await dependencies.observe(decision.actionContract, output);
  } catch {
    return fail('OBSERVATION_FAILED');
  }

  let verification: EffectVerification;
  try {
    verification = await dependencies.verify(
      decision.actionContract,
      observation,
    );
  } catch {
    return fail('EFFECT_UNVERIFIED');
  }
  if (verification.status !== 'verified') {
    return fail('EFFECT_UNVERIFIED');
  }

  const sealedRiver = { ...river, status: 'sealed' as const };
  await dependencies.recordRiver(sealedRiver);
  try {
    await dependencies.project(decision.actionContract, observation);
  } catch {
    return fail('PROJECTION_FAILED');
  }
  return {
    outcome: 'completed',
    context,
    river: sealedRiver,
    observation,
    verification,
  };
}
