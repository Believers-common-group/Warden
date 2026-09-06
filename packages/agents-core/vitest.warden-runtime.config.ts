import { defineConfig } from 'vitest/config';

export default defineConfig({
  root: __dirname,
  test: {
    include: ['test/extensions/wardenTransactionRuntime.test.ts'],
  },
});
