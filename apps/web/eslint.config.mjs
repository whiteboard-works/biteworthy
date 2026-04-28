import shared from '@biteworthy/eslint-config';

export default [
  ...shared,
  {
    ignores: ['.next/**', 'next-env.d.ts'],
  },
];
