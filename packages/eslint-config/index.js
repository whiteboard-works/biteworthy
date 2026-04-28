// Minimal shared ESLint flat config for BiteWorthy TS workspaces.
//
// Kept dependency-free on purpose: each app declares its own framework
// plugins (eslint-config-next in apps/web, expo lint config in
// apps/mobile, plus typescript-eslint where needed). This file just
// supplies the few project-wide preferences and the shared ignore list.

export default [
  {
    rules: {
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  {
    ignores: [
      'dist/**',
      'build/**',
      '.next/**',
      '.expo/**',
      '.turbo/**',
      'node_modules/**',
      '_legacy/**',
      '*.tsbuildinfo',
    ],
  },
];
