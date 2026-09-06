import { defineConfig } from 'vitest/config';

export default defineConfig({
  root: 'packages/agents-core',
  test: {
    include: ['test/extensions/wardenTransactionRuntime.test.ts'],
  },
});
