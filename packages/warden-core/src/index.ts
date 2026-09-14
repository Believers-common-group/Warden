/** A grant that permits specific actions against a resource. */
export interface Authority {
  id: string;
  principalId: string;
  resource: string;
  actions: readonly string[];
}

/** A principal's recorded agreement to a bounded purpose. */
export interface Consent {
  id: string;
  principalId: string;
  purpose: string;
  grantedAt: string;
  expiresAt?: string;
}

/** An approved description of an action that an executor may perform. */
export interface ActionContract<TInput = unknown> {
  id: string;
  actorId: string;
  action: string;
  resource: string;
  input: TInput;
}

/** An authorization result that can proceed to execution. */
export interface AllowedDecision<TInput = unknown> {
  outcome: 'allow';
  actionContract: ActionContract<TInput>;
  authorityId: string;
  consentId?: string;
}

/** An authorization result that cannot proceed to execution. */
export interface DeniedDecision {
  outcome: 'deny';
  reason: string;
  actionContract?: never;
}

/** The complete result of a Warden authorization decision. */
export type DecisionResult<TInput = unknown> =
  | AllowedDecision<TInput>
  | DeniedDecision;

/** Creates an allowed decision with its executable Action Contract. */
export function allow<TInput>(
  actionContract: ActionContract<TInput>,
  authorityId: string,
  consentId?: string,
): AllowedDecision<TInput> {
  return { outcome: 'allow', actionContract, authorityId, consentId };
}

/** Creates a denial that contains no executable Action Contract. */
export function deny(reason: string): DeniedDecision {
  return { outcome: 'deny', reason };
}
