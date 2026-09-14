import { mkdtemp, mkdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';

import {
  ADMISSION_STATUS,
  DESKTOP_COMMANDER_ID,
  GuardedDesktopCommander,
  WardenMcpEvidenceBridge,
  WardenMcpProxy,
  type NormalizedRequest,
} from '../src/index';

describe('WARDEN-MCP-PROXY-001 Phase 3 qualification', () => {
  let sandbox: string;
  let staging: string;
  let outside: string;
  let calls: NormalizedRequest[];
  let proxy: WardenMcpProxy<string>;

  beforeEach(async () => {
    sandbox = await mkdtemp(path.join(tmpdir(), 'warden-mcp-proxy-'));
    staging = path.join(sandbox, 'staging');
    outside = path.join(sandbox, 'outside');
    await Promise.all([mkdir(staging), mkdir(outside)]);
    calls = [];
    proxy = new WardenMcpProxy({
      allowedCallers: ['ZED-ALPHA-001'],
      allowedRoots: [staging],
      executor: {
        execute: async (request) => {
          calls.push(request);
          return 'desktop-commander-result';
        },
      },
    });
  });

  afterEach(async () => rm(sandbox, { recursive: true, force: true }));

  function request(
    targetPath: string,
    overrides: Record<string, unknown> = {},
  ) {
    return {
      requestRef: 'REQ-P3',
      sourceIdentity: 'ZED-ALPHA-001',
      targetService: DESKTOP_COMMANDER_ID,
      tool: { name: 'read_file' },
      arguments: { path: targetPath },
      ...overrides,
    };
  }

  test('P3.1 allowed staging read emits linked admission and execution evidence', async () => {
    const file = path.join(staging, 'example.txt');
    await writeFile(file, 'qualification');
    const result = await proxy.invoke(request(file));

    expect(result.disposition).toBe('ALLOW');
    expect(calls).toHaveLength(1);
    expect(proxy.evidence.admissions[0]).toMatchObject({
      disposition: 'ALLOW',
      admissionStatus: ADMISSION_STATUS,
    });
    expect(proxy.evidence.executions[0]).toMatchObject({
      admissionEventId: proxy.evidence.admissions[0]?.eventId,
      requestFingerprint: result.requestFingerprint,
      status: 'SUCCEEDED',
    });
  });

  test('P3.2 direct Desktop Commander bypass is refused', async () => {
    const guarded = new GuardedDesktopCommander({
      execute: async () => 'unexpected',
    });
    await expect(guarded.invoke({} as NormalizedRequest)).rejects.toThrow(
      'DIRECT_BYPASS_REFUSED',
    );
  });

  test('P3.3 traversal outside staging is denied before execution', async () => {
    const outsideFile = path.join(outside, 'record.txt');
    await writeFile(outsideFile, 'outside');
    const result = await proxy.invoke(
      request(path.join(staging, '..', 'outside', 'record.txt')),
    );
    expect(result).toMatchObject({
      disposition: 'DENY',
      reason: 'RESOLVED_TARGET_OUTSIDE_BOUNDARY',
    });
    expect(calls).toHaveLength(0);
  });

  test('P3.4 a symlink whose resolved target escapes staging is denied', async () => {
    const secret = path.join(outside, 'visible.txt');
    const link = path.join(staging, 'outside-link');
    await writeFile(secret, 'outside');
    await symlink(outside, link, 'junction');
    const result = await proxy.invoke(request(path.join(link, 'visible.txt')));
    expect(result).toMatchObject({
      disposition: 'DENY',
      reason: 'RESOLVED_TARGET_OUTSIDE_BOUNDARY',
    });
    expect(calls).toHaveLength(0);
  });

  test('P3.5 blocked filenames are denied inside an allowed root', async () => {
    const file = path.join(staging, '.env.production');
    await writeFile(file, 'SECRET=value');
    const result = await proxy.invoke(request(file));
    expect(result).toMatchObject({
      disposition: 'DENY',
      reason: 'BLOCKED_FILENAME',
    });
    expect(calls).toHaveLength(0);
  });

  test('P3.6 secret environment injection is stripped and HOME is synthetic', async () => {
    const file = path.join(staging, 'example.txt');
    await writeFile(file, 'qualification');
    const result = await proxy.invoke(
      request(file, {
        executionContext: {
          environment: {
            LANG: 'en_US.UTF-8',
            AWS_SECRET_ACCESS_KEY: 'do-not-forward',
          },
        },
      }),
    );
    expect(result.disposition).toBe('ALLOW');
    expect(calls[0]?.sanitizedEnvironment).toEqual({
      LANG: 'en_US.UTF-8',
      HOME: path.join(staging, '.warden-home'),
    });
  });

  test('P3.7 malformed arguments are denied', async () => {
    const result = await proxy.invoke(
      request(staging, { arguments: { path: 42 } }),
    );
    expect(result).toMatchObject({
      disposition: 'DENY',
      reason: 'MALFORMED_ARGUMENTS',
    });
    expect(calls).toHaveLength(0);
  });

  test('P3.8 execution evidence requires a Warden allow decision', () => {
    const evidence = new WardenMcpEvidenceBridge();
    expect(() => evidence.recordExecution(undefined, 'SUCCEEDED')).toThrow(
      'MISSING_WARDEN_ALLOW_DECISION',
    );
  });

  test('P3.9 an unregistered caller is denied', async () => {
    const file = path.join(staging, 'example.txt');
    await writeFile(file, 'qualification');
    const result = await proxy.invoke(
      request(file, { sourceIdentity: 'UNTRUSTED-CALLER' }),
    );
    expect(result).toMatchObject({
      disposition: 'DENY',
      reason: 'CALLER_NOT_AUTHORIZED',
    });
    expect(calls).toHaveLength(0);
  });

  test('P3.10 unknown tools are denied by default', async () => {
    const result = await proxy.invoke(
      request(staging, { tool: { name: 'delete_everything' } }),
    );
    expect(result).toMatchObject({
      disposition: 'DENY',
      reason: 'MALFORMED_ARGUMENTS',
    });
    expect(calls).toHaveLength(0);
  });
});
