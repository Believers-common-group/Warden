export type WardenDecision = 'ALLOW' | 'DENY' | 'HOLD' | 'BLOCK' | 'DISPUTE';

export type WardenValidationCode =
  | 'ALLOW'
  | 'WARDEN_NOT_ALLOWED'
  | 'WARDEN_SCOPE_MISMATCH'
  | 'WARDEN_EXPIRED'
  | 'TOOLLEASE_EXPIRED'
  | 'TOOLLEASE_SCOPE_MISMATCH'
  | 'DELEGATED_SCOPE_EXCEEDED'
  | 'BATON_BINDING_MISMATCH'
  | 'BATON_EXPIRED'
  | 'BATON_INTEGRITY_INVALID';

export interface WardenValidationResult {
  allowed: boolean;
  code: WardenValidationCode;
}

export interface ActionRequestBinding {
  podId: string;
  digitalMeId: string;
  authenticatedPrincipalReceiptId: string;
  actionId: string;
  capabilityId: string;
  resourceId: string;
  requestDigest: string;
  locationId: string;
  quantity: number;
  unit: string;
}

export interface WardenDecisionReceipt {
  decisionReceiptId: string;
  decision: WardenDecision;
  digitalMeId: string;
  authenticatedPrincipalReceiptId: string;
  actionId: string;
  capabilityId: string;
  resourceId: string;
  requestDigest: string;
  expiresAt: string;
}

export interface ToolLease {
  leaseId: string;
  principalId: string;
  wardenDecisionId: string;
  capabilityId: string;
  targetId: string;
  actionId: string;
  locationId: string;
  maxQuantity: number;
  unit: string;
  expiresAt: string;
  integrityRef: string;
}

export interface SignalBaton {
  batonId: string;
  podId: string;
  wardenDecisionRef: string;
  toolLeaseRef: string;
  idempotencyKey: string;
  expiresAt: string;
  integrityRef: string;
}

const allow = (): WardenValidationResult => ({ allowed: true, code: 'ALLOW' });

const block = (code: Exclude<WardenValidationCode, 'ALLOW'>): WardenValidationResult => ({
  allowed: false,
  code,
});

const isExpired = (expiresAt: string, now: Date): boolean => {
  const expiry = Date.parse(expiresAt);
  return !Number.isFinite(expiry) || expiry <= now.getTime();
};

const isSha256Digest = (value: string): boolean => /^[a-fA-F0-9]{64}$/.test(value);

export function validateActionDecision(
  request: ActionRequestBinding,
  decision: WardenDecisionReceipt,
  now: Date,
): WardenValidationResult {
  if (decision.decision !== 'ALLOW') {
    return block('WARDEN_NOT_ALLOWED');
  }

  if (isExpired(decision.expiresAt, now)) {
    return block('WARDEN_EXPIRED');
  }

  if (
    decision.digitalMeId !== request.digitalMeId ||
    decision.authenticatedPrincipalReceiptId !== request.authenticatedPrincipalReceiptId ||
    decision.actionId !== request.actionId ||
    decision.capabilityId !== request.capabilityId ||
    decision.resourceId !== request.resourceId ||
    decision.requestDigest !== request.requestDigest
  ) {
    return block('WARDEN_SCOPE_MISMATCH');
  }

  return allow();
}

export function validateToolLease(
  request: ActionRequestBinding,
  decision: WardenDecisionReceipt,
  lease: ToolLease,
  now: Date,
): WardenValidationResult {
  const authorization = validateActionDecision(request, decision, now);
  if (!authorization.allowed) {
    return authorization;
  }

  if (isExpired(lease.expiresAt, now)) {
    return block('TOOLLEASE_EXPIRED');
  }

  if (
    lease.principalId !== request.digitalMeId ||
    lease.wardenDecisionId !== decision.decisionReceiptId ||
    lease.capabilityId !== request.capabilityId ||
    lease.targetId !== request.resourceId ||
    lease.actionId !== request.actionId ||
    lease.locationId !== request.locationId ||
    lease.unit !== request.unit ||
    lease.maxQuantity < request.quantity
  ) {
    return block('TOOLLEASE_SCOPE_MISMATCH');
  }

  return allow();
}

export function validateDelegatedToolLease(
  parent: ToolLease,
  child: ToolLease,
): WardenValidationResult {
  if (
    child.principalId !== parent.principalId ||
    child.wardenDecisionId !== parent.wardenDecisionId ||
    child.capabilityId !== parent.capabilityId ||
    child.targetId !== parent.targetId ||
    child.actionId !== parent.actionId ||
    child.locationId !== parent.locationId ||
    child.unit !== parent.unit ||
    child.maxQuantity > parent.maxQuantity ||
    Date.parse(child.expiresAt) > Date.parse(parent.expiresAt)
  ) {
    return block('DELEGATED_SCOPE_EXCEEDED');
  }

  return allow();
}

export function validateSignalBaton(
  baton: SignalBaton,
  request: ActionRequestBinding,
  decision: WardenDecisionReceipt,
  lease: ToolLease,
  now: Date,
): WardenValidationResult {
  if (!isSha256Digest(baton.integrityRef)) {
    return block('BATON_INTEGRITY_INVALID');
  }

  if (isExpired(baton.expiresAt, now)) {
    return block('BATON_EXPIRED');
  }

  if (
    baton.podId !== request.podId ||
    baton.wardenDecisionRef !== decision.decisionReceiptId ||
    baton.toolLeaseRef !== lease.leaseId
  ) {
    return block('BATON_BINDING_MISMATCH');
  }

  return allow();
}
