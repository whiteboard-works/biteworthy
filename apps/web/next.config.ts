import type { NextConfig } from 'next';

const config: NextConfig = {
  reactStrictMode: true,
  transpilePackages: [
    '@biteworthy/api-types',
    '@biteworthy/filter-engine',
    '@biteworthy/ui-tokens',
    '@biteworthy/version-history',
  ],
  experimental: {
    typedRoutes: true,
  },
};

export default config;
