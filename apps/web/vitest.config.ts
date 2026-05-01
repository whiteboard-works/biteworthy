import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

/**
 * Phase post-5 — Discovered followup #1 (web side).
 *
 * jsdom environment so `.tsx` render tests (via @testing-library/react)
 * can use document/window. The @vitejs/plugin-react adds the
 * automatic JSX runtime so test files don't need `import React`.
 *
 * Pure-TS fetcher tests still work because they don't touch DOM APIs;
 * jsdom just adds them rather than removing Node primitives.
 *
 * Per-file override: any pure-Node test that wants to be explicit can
 * add `// @vitest-environment node` at the top.
 */
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'],
    globals: true,
    include: ['src/**/__tests__/**/*.{test,spec}.{ts,tsx}'],
  },
});
