import shared from '@biteworthy/eslint-config';

export default [
  ...shared,
  {
    ignores: ['.expo/**', 'dist/**', 'expo-env.d.ts'],
  },
];
