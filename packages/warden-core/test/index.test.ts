import { describe, expect, expectTypeOf, test } from 'vitest';

import { deny, type DeniedDecision } from '../src/index';

describe('Warden decisions', () => {
  test('denied decisions never produce executable action contracts', () => {
    const decision = deny('Missing authority');

    expect(decision).toEqual({
      outcome: 'deny',
      reason: 'Missing authority',
    });
    expect(decision).not.toHaveProperty('actionContract');
    expectTypeOf<DeniedDecision['actionContract']>().toEqualTypeOf<undefined>();
  });
});
