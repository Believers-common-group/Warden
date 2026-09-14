import { createHash, randomUUID } from 'node:crypto';
import { realpath } from 'node:fs/promises';
import path from 'node:path';

export const WARDEN_MCP_PROXY_ID = 'WARDEN-MCP-PROXY-001';
export const DESKTOP_COMMANDER_ID = 'DESKTOP-COMMANDER-MCP-001';
export const ADMISSION_STATUS = 'QUALIFICATION_ONLY' as const;

export type SupportedTool = 'read_file' | 'start_process';

export interface ProxyRequest {
  requestRef: string;
  sourceIdentity: string;
  targetService: typeof DESKTOP_COMMANDER_ID;
  tool: { name: SupportedTool };
  arguments: { path?: string; command?: string };
  executionContext?: { cwd?: string; environment?: Record<string, string> };
}

export interface NormalizedRequest extends ProxyRequest {
  capability: 'FILE_READ' | 'PROCESS_START';
  canonicalPath?: string;
  resolvedTarget?: string;
  sanitizedEnvironment: Readonly<Record<string, string>>;
}

export interface AdmissionEvidence {
  kind: 'MCP_ADMISSION_DECISION';
  eventId: string;
  requestFingerprint: string;
  sourceIdentity: string;
  requestedTool: string;
  disposition: 'ALLOW' | 'DENY';
  reason: string;
  policyRef: 'WARDEN-MCP-PROXY-001/R0.1';
  admissionStatus: typeof ADMISSION_STATUS;
  recordedAt: string;
}

export interface ExecutionEvidence {
  kind: 'MCP_EXECUTION_OUTCOME';
  eventId: string;
  admissionEventId: string;
  requestFingerprint: string;
  executor: typeof DESKTOP_COMMANDER_ID;
  status: 'SUCCEEDED' | 'FAILED';
  recordedAt: string;
}

export type ProxyResult<T = unknown> =
  | { disposition: 'ALLOW'; requestFingerprint: string; output: T }
  | { disposition: 'DENY'; requestFingerprint: string; reason: string };

export interface DesktopCommanderExecutor<T = unknown> {
  execute(request: NormalizedRequest): Promise<T>;
}

export interface McpServiceRegistration {
  identity: string;
  exposure: 'public' | 'private';
  callableBy: readonly string[];
  admissionStatus: typeof ADMISSION_STATUS;
}

export interface WardenMcpDeploymentManifest {
  services: readonly McpServiceRegistration[];
}

export type DeploymentValidation =
  | { valid: true; manifest: WardenMcpDeploymentManifest }
  | { valid: false; reason: string };

/** Validates that deployment registration has no route around the proxy. */
export function validateWardenMcpDeployment(
  manifest: WardenMcpDeploymentManifest,
): DeploymentValidation {
  const proxies = manifest.services.filter(
    (service) => service.identity === WARDEN_MCP_PROXY_ID,
  );
  const targets = manifest.services.filter(
    (service) => service.identity === DESKTOP_COMMANDER_ID,
  );
  if (proxies.length !== 1)
    return { valid: false, reason: 'PROXY_REGISTRATION_INVALID' };
  if (targets.length !== 1)
    return { valid: false, reason: 'TARGET_REGISTRATION_INVALID' };

  const proxy = proxies[0];
  const target = targets[0];
  if (!proxy || proxy.exposure !== 'public') {
    return { valid: false, reason: 'PROXY_MUST_BE_PUBLIC_ENTRYPOINT' };
  }
  if (
    !target ||
    target.exposure !== 'private' ||
    target.callableBy.length !== 1 ||
    target.callableBy[0] !== WARDEN_MCP_PROXY_ID
  ) {
    return { valid: false, reason: 'DIRECT_TARGET_ROUTE_FORBIDDEN' };
  }
  if (
    proxy.admissionStatus !== ADMISSION_STATUS ||
    target.admissionStatus !== ADMISSION_STATUS
  ) {
    return { valid: false, reason: 'QUALIFICATION_BOUNDARY_REQUIRED' };
  }
  return { valid: true, manifest };
}

export const QUALIFICATION_DEPLOYMENT_MANIFEST: WardenMcpDeploymentManifest =
  Object.freeze({
    services: Object.freeze([
      Object.freeze({
        identity: WARDEN_MCP_PROXY_ID,
        exposure: 'public' as const,
        callableBy: Object.freeze(['DEVELOPER-TOOLING-DOOR-001']),
        admissionStatus: ADMISSION_STATUS,
      }),
      Object.freeze({
        identity: DESKTOP_COMMANDER_ID,
        exposure: 'private' as const,
        callableBy: Object.freeze([WARDEN_MCP_PROXY_ID]),
        admissionStatus: ADMISSION_STATUS,
      }),
    ]),
  });

const proxyCapability = Object.freeze({ proxy: WARDEN_MCP_PROXY_ID });

/** WARDEN-MCP-PROXY-IDENTITY-001: resolves only explicitly admitted callers. */
export class WardenMcpProxyIdentity {
  readonly #allowedCallers: ReadonlySet<string>;

  constructor(allowedCallers: Iterable<string>) {
    this.#allowedCallers = new Set(allowedCallers);
  }

  authorize(sourceIdentity: string): boolean {
    return this.#allowedCallers.has(sourceIdentity);
  }
}

/** WARDEN-MCP-REQUEST-NORMALIZER-001: parses and canonicalizes requests. */
export class WardenMcpRequestNormalizer {
  readonly #allowedEnvironment = new Set([
    'LANG',
    'LC_ALL',
    'PATH',
    'SYSTEMROOT',
    'TEMP',
    'TMP',
  ]);

  async normalize(
    value: unknown,
    syntheticHome: string,
  ): Promise<NormalizedRequest> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('MALFORMED_REQUEST');
    }
    const candidate = value as Partial<ProxyRequest>;
    if (
      typeof candidate.requestRef !== 'string' ||
      candidate.requestRef.length === 0 ||
      typeof candidate.sourceIdentity !== 'string' ||
      candidate.targetService !== DESKTOP_COMMANDER_ID ||
      !candidate.tool ||
      (candidate.tool.name !== 'read_file' &&
        candidate.tool.name !== 'start_process') ||
      !candidate.arguments ||
      typeof candidate.arguments !== 'object'
    ) {
      throw new Error('MALFORMED_ARGUMENTS');
    }

    const capability =
      candidate.tool.name === 'read_file' ? 'FILE_READ' : 'PROCESS_START';
    const requestedPath =
      capability === 'FILE_READ'
        ? candidate.arguments.path
        : candidate.executionContext?.cwd;
    if (
      typeof requestedPath !== 'string' ||
      requestedPath.length === 0 ||
      requestedPath.includes('\0')
    ) {
      throw new Error('MALFORMED_ARGUMENTS');
    }
    if (
      capability === 'PROCESS_START' &&
      typeof candidate.arguments.command !== 'string'
    ) {
      throw new Error('MALFORMED_ARGUMENTS');
    }

    const canonicalPath = path.resolve(requestedPath);
    let resolvedTarget: string;
    try {
      resolvedTarget = await realpath(canonicalPath);
    } catch {
      throw new Error('UNRESOLVED_TARGET');
    }
    const environment: Record<string, string> = { HOME: syntheticHome };
    for (const [key, envValue] of Object.entries(
      candidate.executionContext?.environment ?? {},
    )) {
      if (this.#allowedEnvironment.has(key)) environment[key] = envValue;
    }

    return {
      requestRef: candidate.requestRef,
      sourceIdentity: candidate.sourceIdentity,
      targetService: DESKTOP_COMMANDER_ID,
      tool: { name: candidate.tool.name },
      arguments: { ...candidate.arguments },
      executionContext: {
        ...candidate.executionContext,
        cwd: canonicalPath,
        environment,
      },
      capability,
      canonicalPath,
      resolvedTarget,
      sanitizedEnvironment: Object.freeze(environment),
    };
  }
}

/** WARDEN-MCP-BOUNDARY-ENFORCER-001: authorizes the resolved target, never raw input. */
export class WardenMcpBoundaryEnforcer {
  readonly #roots: readonly string[];

  constructor(allowedRoots: Iterable<string>) {
    this.#roots = [...allowedRoots].map((root) => path.resolve(root));
  }

  get syntheticHome(): string {
    const root = this.#roots[0];
    if (!root) throw new Error('NO_ALLOWED_ROOTS');
    return path.join(root, '.warden-home');
  }

  authorize(
    request: NormalizedRequest,
  ): { allowed: true } | { allowed: false; reason: string } {
    if (!request.resolvedTarget)
      return { allowed: false, reason: 'MISSING_RESOLVED_TARGET' };
    const target = path.resolve(request.resolvedTarget);
    const withinRoot = this.#roots.some(
      (root) => target === root || target.startsWith(`${root}${path.sep}`),
    );
    if (!withinRoot)
      return { allowed: false, reason: 'RESOLVED_TARGET_OUTSIDE_BOUNDARY' };

    const normalizedSegments = target
      .split(/[\\/]+/)
      .map((segment) => segment.toLowerCase());
    const base = normalizedSegments.at(-1) ?? '';
    const blocked =
      base === '.env' ||
      base.startsWith('.env.') ||
      base.endsWith('.pem') ||
      base.endsWith('.key') ||
      base.startsWith('secrets') ||
      base.startsWith('credentials') ||
      (base === 'config.json' && normalizedSegments.at(-2) === '.docker');
    if (blocked) return { allowed: false, reason: 'BLOCKED_FILENAME' };
    return { allowed: true };
  }
}

/** WARDEN-MCP-EVIDENCE-BRIDGE-001: emits linked admission and execution facts. */
export class WardenMcpEvidenceBridge {
  readonly admissions: AdmissionEvidence[] = [];
  readonly executions: ExecutionEvidence[] = [];

  recordAdmission(
    input: Omit<
      AdmissionEvidence,
      'kind' | 'eventId' | 'policyRef' | 'admissionStatus' | 'recordedAt'
    >,
  ): AdmissionEvidence {
    const event: AdmissionEvidence = {
      ...input,
      kind: 'MCP_ADMISSION_DECISION',
      eventId: randomUUID(),
      policyRef: 'WARDEN-MCP-PROXY-001/R0.1',
      admissionStatus: ADMISSION_STATUS,
      recordedAt: new Date().toISOString(),
    };
    this.admissions.push(event);
    return event;
  }

  recordExecution(
    admission: AdmissionEvidence | undefined,
    status: ExecutionEvidence['status'],
  ): ExecutionEvidence {
    if (!admission || admission.disposition !== 'ALLOW')
      throw new Error('MISSING_WARDEN_ALLOW_DECISION');
    const event: ExecutionEvidence = {
      kind: 'MCP_EXECUTION_OUTCOME',
      eventId: randomUUID(),
      admissionEventId: admission.eventId,
      requestFingerprint: admission.requestFingerprint,
      executor: DESKTOP_COMMANDER_ID,
      status,
      recordedAt: new Date().toISOString(),
    };
    this.executions.push(event);
    return event;
  }
}

/** Target wrapper whose invocation capability is held only by WardenMcpProxy. */
export class GuardedDesktopCommander<T = unknown> {
  readonly #executor: DesktopCommanderExecutor<T>;

  constructor(executor: DesktopCommanderExecutor<T>) {
    this.#executor = executor;
  }

  async invoke(request: NormalizedRequest, capability?: object): Promise<T> {
    if (capability !== proxyCapability)
      throw new Error('DIRECT_BYPASS_REFUSED');
    return this.#executor.execute(request);
  }
}

export interface WardenMcpProxyOptions<T> {
  allowedCallers: Iterable<string>;
  allowedRoots: Iterable<string>;
  executor: DesktopCommanderExecutor<T>;
  evidence?: WardenMcpEvidenceBridge;
}

/** WARDEN-MCP-PROXY-001 R0.1 mandatory mediation pipeline. */
export class WardenMcpProxy<T = unknown> {
  readonly identity: WardenMcpProxyIdentity;
  readonly normalizer = new WardenMcpRequestNormalizer();
  readonly boundary: WardenMcpBoundaryEnforcer;
  readonly evidence: WardenMcpEvidenceBridge;
  readonly target: GuardedDesktopCommander<T>;

  constructor(options: WardenMcpProxyOptions<T>) {
    this.identity = new WardenMcpProxyIdentity(options.allowedCallers);
    this.boundary = new WardenMcpBoundaryEnforcer(options.allowedRoots);
    this.evidence = options.evidence ?? new WardenMcpEvidenceBridge();
    this.target = new GuardedDesktopCommander(options.executor);
  }

  async invoke(value: unknown): Promise<ProxyResult<T>> {
    const fingerprint = fingerprintOf(value);
    let normalized: NormalizedRequest;
    try {
      normalized = await this.normalizer.normalize(
        value,
        this.boundary.syntheticHome,
      );
    } catch (error) {
      return this.deny(
        value,
        fingerprint,
        error instanceof Error ? error.message : 'MALFORMED_REQUEST',
      );
    }
    if (!this.identity.authorize(normalized.sourceIdentity)) {
      return this.deny(normalized, fingerprint, 'CALLER_NOT_AUTHORIZED');
    }
    const boundary = this.boundary.authorize(normalized);
    if (!boundary.allowed)
      return this.deny(normalized, fingerprint, boundary.reason);

    const admission = this.evidence.recordAdmission({
      requestFingerprint: fingerprint,
      sourceIdentity: normalized.sourceIdentity,
      requestedTool: normalized.tool.name,
      disposition: 'ALLOW',
      reason: 'ALL_CHECKS_PASSED',
    });
    try {
      const output = await this.target.invoke(normalized, proxyCapability);
      this.evidence.recordExecution(admission, 'SUCCEEDED');
      return { disposition: 'ALLOW', requestFingerprint: fingerprint, output };
    } catch (error) {
      this.evidence.recordExecution(admission, 'FAILED');
      throw error;
    }
  }

  private deny(
    value: unknown,
    fingerprint: string,
    reason: string,
  ): ProxyResult<T> {
    const candidate =
      value && typeof value === 'object'
        ? (value as Partial<ProxyRequest>)
        : {};
    this.evidence.recordAdmission({
      requestFingerprint: fingerprint,
      sourceIdentity:
        typeof candidate.sourceIdentity === 'string'
          ? candidate.sourceIdentity
          : 'UNRESOLVED',
      requestedTool:
        candidate.tool && typeof candidate.tool.name === 'string'
          ? candidate.tool.name
          : 'UNRESOLVED',
      disposition: 'DENY',
      reason,
    });
    return { disposition: 'DENY', requestFingerprint: fingerprint, reason };
  }
}

function fingerprintOf(value: unknown): string {
  let serialized: string;
  try {
    serialized = stableStringify(value);
  } catch {
    serialized = String(value);
  }
  return createHash('sha256').update(serialized).digest('hex');
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => `${JSON.stringify(key)}:${stableStringify(entry)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}
