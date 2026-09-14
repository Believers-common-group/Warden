import { describe, expect, it } from 'vitest';
import {
  admitTarget,
  verifyAdmission,
  type AdmissionDependencies,
} from '../src/index.js';

const now = () => '2026-08-27T18:00:00.000Z';
let nextId = 0;
const base: AdmissionDependencies = {
  resolve: async () => '127.0.0.1',
  connect: async () => undefined,
  request: async (_url) =>
    new Response('{}', {
      status: 200,
      headers: { 'x-warden-service-id': 'alpha-demo' },
    }),
  now,
  id: () => `id-${++nextId}`,
};

describe('audit target admission', () => {
  it('admits and binds a reachable, identified, ready target', async () => {
    const result = await admitTarget(
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'alpha-demo' },
      base,
    );
    expect(result.outcome).toBe('admitted');
    expect(result.receipt.states.map((item) => item.state)).toEqual([
      'DISCOVERED',
      'RESOLVED',
      'REACHABLE',
      'RESPONDING',
      'IDENTITY_VERIFIED',
      'READY',
      'ADMITTED',
    ]);
    expect(result.receipt.states.every((item) => item.passed)).toBe(true);
  });

  it.each([
    [
      'TARGET_CONFIG_INVALID',
      { url: 'file:///tmp/app', expectedServiceId: '' },
      {},
    ],
    [
      'TARGET_NOT_LISTENING',
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'alpha-demo' },
      {
        connect: async () => {
          throw new Error('refused');
        },
      },
    ],
    [
      'TARGET_UNREACHABLE_FROM_AUDITOR',
      { url: 'http://wsl.internal:4311', expectedServiceId: 'alpha-demo' },
      {
        resolve: async () => {
          throw new Error('no route');
        },
      },
    ],
    [
      'WRONG_SERVICE',
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'other' },
      {},
    ],
    [
      'HTTP_INTERSTITIAL',
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'alpha-demo' },
      {
        request: async () =>
          new Response('<title>Privacy error</title>', { status: 200 }),
      },
    ],
    [
      'READINESS_FAILED',
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'alpha-demo' },
      {
        request: async (url: string) =>
          url.endsWith('/readyz')
            ? new Response('{}', { status: 503 })
            : new Response('{}', {
                status: 200,
                headers: { 'x-warden-service-id': 'alpha-demo' },
              }),
      },
    ],
  ])('returns %s', async (reason, config, overrides) => {
    const result = await admitTarget(config, { ...base, ...overrides });
    expect(result.outcome).toBe('blocked');
    if (result.outcome === 'blocked') expect(result.reason).toBe(reason);
  });

  it('detects a target changed after admission', async () => {
    const admitted = await admitTarget(
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'alpha-demo' },
      base,
    );
    expect(admitted.outcome).toBe('admitted');
    if (admitted.outcome !== 'admitted') return;
    const changed = await verifyAdmission(
      admitted.binding,
      { url: 'http://127.0.0.1:4311', expectedServiceId: 'alpha-demo' },
      {
        ...base,
        request: async (url) =>
          new Response(url.endsWith('/readyz') ? '{}' : '{"revision":2}', {
            status: 200,
            headers: { 'x-warden-service-id': 'alpha-demo' },
          }),
      },
    );
    expect(changed.outcome).toBe('blocked');
    if (changed.outcome === 'blocked')
      expect(changed.reason).toBe('TARGET_CHANGED_AFTER_ADMISSION');
  });
});
