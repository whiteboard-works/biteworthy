// Shared ESLint flat config for all TS apps and packages.
// Each app extends this with its own framework rules (Next, Expo, etc.).

import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default [
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/consistent-type-imports': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  {
    ignores: ['dist/**', '.next/**', '.expo/**', 'node_modules/**', '_legacy/**'],
  },
];
