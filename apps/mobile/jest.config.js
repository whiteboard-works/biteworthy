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
 *
 * No `setupFilesAfterEnv` — `@testing-library/react-native` v13's
 * main entry does `require('./matchers/extend-expect')` as a
 * side-effect import, so matchers (`toBeOnTheScreen`, etc.) are
 * auto-registered the first time any test file imports from the
 * package. PR #191 added a setup file to do this explicitly, but
 * the config key was typo'd (`setupFilesAfterEach` instead of
 * `setupFilesAfterEnv`) so the file never loaded — and the import
 * path it used (`'.../extend-expect'`) was removed in v13. Tests
 * passed anyway because of the auto-registration. PR #195 deleted
 * the dead config + setup file.
 */
module.exports = {
  preset: 'jest-expo',
  transformIgnorePatterns: [
    'node_modules/(?!(?:.pnpm/)?(?:(jest-)?react-native|@react-native|@react-native-community|expo|@expo|react-native-.+|@react-navigation/.+))',
  ],
};
