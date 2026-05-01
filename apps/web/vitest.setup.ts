/**
 * Phase post-5 — vitest setup file.
 *
 * Loads @testing-library/jest-dom matchers (toBeInTheDocument,
 * toHaveAttribute, etc.) so render tests read like the rest of the
 * ecosystem. Runs once per worker, before any test file.
 */
import '@testing-library/jest-dom/vitest';
