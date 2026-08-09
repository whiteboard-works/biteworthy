import { defineConfig } from 'vitest/config';

/**
 * Only `src/`. Vitest's default include also matches compiled tests under
 * `dist/`, which are stale by definition — deleting a source file leaves
 * its build artifact behind, and the zombie then fails against exports
 * that no longer exist. That is exactly what happened when the dead
 * filter mirror was removed: `dist/rails-parity.test.js` survived and
 * reported `applyProfile is not a function`.
 *
 * `dist/` is gitignored so CI never saw it, which is the worse half —
 * the failure only reaches whoever has built the package locally.
 */
export default defineConfig({
  test: {
    include: ['src/**/*.{test,spec}.ts'],
  },
});
