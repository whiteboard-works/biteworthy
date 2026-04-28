import type { Config } from 'tailwindcss';
import { colors, fontSize, radius, space } from '@biteworthy/ui-tokens';

const config: Config = {
  content: ['./src/**/*.{ts,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        bite: colors.bite,
        'bite-dark': colors.biteDark,
        'bite-light': colors.biteLight,
        ok: colors.ok,
        warn: colors.warn,
        hide: colors.hide,
        danger: colors.danger,
      },
      borderRadius: {
        'bw-sm': `${radius.sm}px`,
        'bw-md': `${radius.md}px`,
        'bw-lg': `${radius.lg}px`,
        'bw-pill': `${radius.pill}px`,
      },
      spacing: Object.fromEntries(
        Object.entries(space).map(([k, v]) => [`bw-${k}`, `${v}px`]),
      ),
      fontSize: Object.fromEntries(
        Object.entries(fontSize).map(([k, v]) => [`bw-${k}`, `${v}px`]),
      ),
    },
  },
  plugins: [],
};

export default config;
