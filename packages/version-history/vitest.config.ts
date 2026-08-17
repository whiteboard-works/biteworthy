import { defineConfig } from 'vitest/config';

// Explicit include so a stale compiled test in dist/ can never run
// (the filter-engine zombie-dist lesson).
export default defineConfig({
  test: {
    include: ['src/**/*.{test,spec}.ts'],
  },
});
