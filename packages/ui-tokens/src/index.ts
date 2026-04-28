/**
 * Shared design tokens for web (Tailwind) and mobile (RN StyleSheet).
 * Keep this file the single source of truth — no per-app divergence.
 */

export const colors = {
  // Brand
  bite: '#E14E2A',
  biteDark: '#A8351A',
  biteLight: '#FFE9E1',

  // Status
  ok: '#2F9E44',
  warn: '#F59F00',
  hide: '#868E96',
  danger: '#E03131',

  // Surface
  bg: '#FFFFFF',
  bgAlt: '#F7F5F2',
  border: '#E6E2DD',
  text: '#1A1A1A',
  textMuted: '#5C5C5C',
} as const;

export const space = {
  px: 1,
  '0_5': 2,
  '1': 4,
  '2': 8,
  '3': 12,
  '4': 16,
  '5': 20,
  '6': 24,
  '8': 32,
  '10': 40,
  '12': 48,
  '16': 64,
} as const;

export const radius = {
  sm: 6,
  md: 10,
  lg: 16,
  pill: 999,
} as const;

export const fontSize = {
  xs: 12,
  sm: 14,
  base: 16,
  lg: 18,
  xl: 20,
  '2xl': 24,
  '3xl': 30,
  '4xl': 36,
} as const;
