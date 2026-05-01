/**
 * Phase post-5 — jest config for the mobile app.
 *
 * jest-expo is the canonical preset for Expo SDK 52. Without it,
 * importing any screen module fails with "Cannot use import
 * statement outside a module" (the issue the Discovered note has
 * flagged since Phase 3.5).
 *
 * Override `transformIgnorePatterns` because pnpm's nested layout
 * — `node_modules/.pnpm/@react-native+js-polyfills@.../node_modules/...`
 * — doesn't match the upstream pattern that assumes a flat npm
 * layout. The override permits transformation for any path that
 * mentions react-native, expo, or @react-native, regardless of
 * pnpm's package directory naming.
 *
 * Existing pure-TS tests under __tests__/lib/ continue to pass —
 * they don't import react-native modules directly (they mock
 * expo-secure-store / fetch at the boundary).
 */
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEach: ['./jest.setup.ts'],
  transformIgnorePatterns: [
    'node_modules/(?!(?:.pnpm/)?(?:(jest-)?react-native|@react-native|@react-native-community|expo|@expo|react-native-.+|@react-navigation/.+))',
  ],
};
