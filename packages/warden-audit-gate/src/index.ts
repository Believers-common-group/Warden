import { createHash, randomUUID } from 'node:crypto';
import { lookup } from 'node:dns/promises';
import { Socket } from 'node:net';

export const ADMISSION_STATES = [
  'DISCOVERED',
  'RESOLVED',
  'REACHABLE',
  'RESPONDING',
  'IDENTITY_VERIFIED',
  'READY',
  'ADMITTED',
] as const;

export type AdmissionState = (typeof ADMISSION_STATES)[number];
export type BlockReason =
  | 'TARGET_NOT_LISTENING'
  | 'TARGET_UNREACHABLE_FROM_AUDITOR'
  | 'WRONG_SERVICE'
  | 'HTTP_INTERSTITIAL'
  | 'READINESS_FAILED'
  | 'TARGET_CHANGED_AFTER_ADMISSION'
  | 'TARGET_CONFIG_INVALID';

export interface TargetConfig {
  url: string;
  expectedServiceId: string;
  readinessPath?: string;
  timeoutMs?: number;
}

export interface StateEvidence {
  state: AdmissionState;
  passed: boolean;
  detail: string;
  observedAt: string;
}

export interface AuditBinding {
  id: string;
  targetUrl: string;
  serviceId: string;
  resolvedAddress: string;
  fingerprint: string;
  admittedAt: string;
}

export interface EvidenceReceipt {
  id: string;
  kind: 'AUDIT_TARGET_ADMISSION';
  status: 'admitted' | 'blocked';
  targetUrl: string;
  observedAt: string;
  states: readonly StateEvidence[];
  blockReason?: BlockReason;
  bindingId?: string;
}

export type AdmissionResult =
  | { outcome: 'admitted'; binding: AuditBinding; receipt: EvidenceReceipt }
  | { outcome: 'blocked'; reason: BlockReason; receipt: EvidenceReceipt };

export interface AdmissionDependencies {
  resolve(hostname: string): Promise<string>;
  connect(host: string, port: number, timeoutMs: number): Promise<void>;
  request(url: string, timeoutMs: number): Promise<Response>;
  now(): string;
  id(): string;
}

const defaults: AdmissionDependencies = {
  async resolve(hostname) {
    return (await lookup(hostname)).address;
  },
  connect(host, port, timeoutMs) {
    return new Promise((resolve, reject) => {
      const socket = new Socket();
      const done = (error?: Error) => {
        socket.destroy();
        if (error) reject(error);
        else resolve();
      };
      socket.setTimeout(timeoutMs, () => done(new Error('timeout')));
      socket.once('error', done);
      socket.connect(port, host, () => done());
    });
  },
  request(url, timeoutMs) {
    return fetch(url, {
      redirect: 'follow',
      signal: AbortSignal.timeout(timeoutMs),
    });
  },
  now: () => new Date().toISOString(),
  id: () => randomUUID(),
};

function receipt(
  deps: AdmissionDependencies,
  targetUrl: string,
  states: StateEvidence[],
  status: 'admitted' | 'blocked',
  blockReason?: BlockReason,
  bindingId?: string,
): EvidenceReceipt {
  return {
    id: deps.id(),
    kind: 'AUDIT_TARGET_ADMISSION',
    status,
    targetUrl,
    observedAt: deps.now(),
    states,
    blockReason,
    bindingId,
  };
}

function state(
  deps: AdmissionDependencies,
  name: AdmissionState,
  passed: boolean,
  detail: string,
): StateEvidence {
  return { state: name, passed, detail, observedAt: deps.now() };
}

function block(
  deps: AdmissionDependencies,
  targetUrl: string,
  states: StateEvidence[],
  reason: BlockReason,
  detail: string,
  failedState: AdmissionState,
): AdmissionResult {
  states.push(state(deps, failedState, false, detail));
  return {
    outcome: 'blocked',
    reason,
    receipt: receipt(deps, targetUrl, states, 'blocked', reason),
  };
}

function mergeDependencies(
  overrides?: Partial<AdmissionDependencies>,
): AdmissionDependencies {
  return { ...defaults, ...overrides };
}

function fingerprint(
  serviceId: string,
  responseUrl: string,
  body: string,
): string {
  return createHash('sha256')
    .update(`${serviceId}\n${responseUrl}\n${body}`)
    .digest('hex');
}

export async function admitTarget(
  config: TargetConfig,
  overrides?: Partial<AdmissionDependencies>,
): Promise<AdmissionResult> {
  const deps = mergeDependencies(overrides);
  const states: StateEvidence[] = [];
  let target: URL;
  try {
    target = new URL(config.url);
    if (
      !['http:', 'https:'].includes(target.protocol) ||
      !config.expectedServiceId.trim()
    )
      throw new Error('invalid');
  } catch {
    return block(
      deps,
      config.url,
      states,
      'TARGET_CONFIG_INVALID',
      'Use an HTTP(S) URL and expected service identity.',
      'DISCOVERED',
    );
  }
  const timeout = config.timeoutMs ?? 3000;
  states.push(
    state(
      deps,
      'DISCOVERED',
      true,
      `Target ${target.href} discovered from explicit configuration.`,
    ),
  );
  let address: string;
  try {
    address = await deps.resolve(target.hostname);
    states.push(
      state(
        deps,
        'RESOLVED',
        true,
        `${target.hostname} resolved to ${address}.`,
      ),
    );
  } catch (error) {
    return block(
      deps,
      target.href,
      states,
      'TARGET_UNREACHABLE_FROM_AUDITOR',
      `Auditor DNS resolution failed: ${String(error)}.`,
      'RESOLVED',
    );
  }
  try {
    await deps.connect(
      address,
      Number(target.port || (target.protocol === 'https:' ? 443 : 80)),
      timeout,
    );
    states.push(
      state(
        deps,
        'REACHABLE',
        true,
        `TCP connection succeeded from auditor to ${address}.`,
      ),
    );
  } catch (error) {
    const reason = ['127.0.0.1', '::1', 'localhost'].includes(target.hostname)
      ? 'TARGET_NOT_LISTENING'
      : 'TARGET_UNREACHABLE_FROM_AUDITOR';
    return block(
      deps,
      target.href,
      states,
      reason,
      `TCP connection failed from auditor: ${String(error)}.`,
      'REACHABLE',
    );
  }
  let response: Response;
  let body: string;
  try {
    response = await deps.request(target.href, timeout);
    body = await response.text();
  } catch (error) {
    return block(
      deps,
      target.href,
      states,
      'TARGET_UNREACHABLE_FROM_AUDITOR',
      `HTTP request failed from auditor: ${String(error)}.`,
      'RESPONDING',
    );
  }
  if (
    response.url.startsWith('chrome-error:') ||
    /chromewebdata|privacy error|site cannot be reached/i.test(body)
  ) {
    return block(
      deps,
      target.href,
      states,
      'HTTP_INTERSTITIAL',
      'HTTP navigation produced a browser interstitial or Chrome error page.',
      'RESPONDING',
    );
  }
  if (!response.ok) {
    return block(
      deps,
      target.href,
      states,
      'TARGET_UNREACHABLE_FROM_AUDITOR',
      `Target returned HTTP ${response.status}.`,
      'RESPONDING',
    );
  }
  states.push(
    state(deps, 'RESPONDING', true, `Target returned HTTP ${response.status}.`),
  );
  const serviceId = response.headers.get('x-warden-service-id') ?? '';
  if (serviceId !== config.expectedServiceId) {
    return block(
      deps,
      target.href,
      states,
      'WRONG_SERVICE',
      `Expected ${config.expectedServiceId}; observed ${serviceId || 'no identity header'}.`,
      'IDENTITY_VERIFIED',
    );
  }
  states.push(
    state(
      deps,
      'IDENTITY_VERIFIED',
      true,
      `Service identity ${serviceId} matched.`,
    ),
  );
  const readyUrl = new URL(config.readinessPath ?? '/readyz', target);
  let ready: Response;
  try {
    ready = await deps.request(readyUrl.href, timeout);
  } catch (error) {
    return block(
      deps,
      target.href,
      states,
      'READINESS_FAILED',
      `Readiness request failed: ${String(error)}.`,
      'READY',
    );
  }
  if (!ready.ok || ready.headers.get('x-warden-service-id') !== serviceId) {
    return block(
      deps,
      target.href,
      states,
      'READINESS_FAILED',
      `Readiness returned HTTP ${ready.status} or inconsistent identity.`,
      'READY',
    );
  }
  states.push(
    state(
      deps,
      'READY',
      true,
      `${readyUrl.pathname} returned HTTP ${ready.status} with matching identity.`,
    ),
  );
  const binding: AuditBinding = {
    id: deps.id(),
    targetUrl: target.href,
    serviceId,
    resolvedAddress: address,
    fingerprint: fingerprint(serviceId, response.url, body),
    admittedAt: deps.now(),
  };
  states.push(
    state(deps, 'ADMITTED', true, `Audit binding ${binding.id} created.`),
  );
  return {
    outcome: 'admitted',
    binding,
    receipt: receipt(
      deps,
      target.href,
      states,
      'admitted',
      undefined,
      binding.id,
    ),
  };
}

export async function verifyAdmission(
  binding: AuditBinding,
  config: TargetConfig,
  overrides?: Partial<AdmissionDependencies>,
): Promise<AdmissionResult> {
  const result = await admitTarget(config, overrides);
  if (result.outcome === 'blocked') return result;
  if (
    result.binding.targetUrl !== binding.targetUrl ||
    result.binding.serviceId !== binding.serviceId ||
    result.binding.resolvedAddress !== binding.resolvedAddress ||
    result.binding.fingerprint !== binding.fingerprint
  ) {
    const deps = mergeDependencies(overrides);
    const states = [...result.receipt.states.slice(0, -1)];
    return block(
      deps,
      config.url,
      states,
      'TARGET_CHANGED_AFTER_ADMISSION',
      'Current target observation no longer matches the admitted binding.',
      'ADMITTED',
    );
  }
  return result;
}
