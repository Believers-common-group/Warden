import { describe, expect, expectTypeOf, test } from 'vitest';

import type {
  DigitalMePrincipal,
  GitHubIdentity,
  PrincipalResolver,
} from '../src/index';

describe('Warden identity boundaries', () => {
  test('GitHub authentication does not imply Warden authority', () => {
    const identity: GitHubIdentity = {
      provider: 'github',
      subject: 'github:42',
      authenticatedAt: '2026-08-20T00:00:00.000Z',
      login: 'octocat',
      userId: 42,
    };

    expect(identity.provider).toBe('github');
    expect(identity).not.toHaveProperty('authority');
    expectTypeOf<GitHubIdentity>().not.toHaveProperty('authority');
  });

  test('principal resolution is separate from provider identity', async () => {
    const identity: GitHubIdentity = {
      provider: 'github',
      subject: 'github:42',
      authenticatedAt: '2026-08-20T00:00:00.000Z',
      login: 'octocat',
      userId: 42,
    };
    const principal: DigitalMePrincipal = {
      id: 'digitalme:alice',
      kind: 'person',
      displayName: 'Alice',
    };
    const resolver: PrincipalResolver = {
      resolve: async () => principal,
    };

    const resolved = await resolver.resolve(identity);

    expect(resolved).toEqual(principal);
    expect(resolved).not.toBe(identity);
    expect(resolved).not.toHaveProperty('provider');
  });
});
