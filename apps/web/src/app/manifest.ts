import type { MetadataRoute } from 'next';
import { colors } from '@biteworthy/ui-tokens';

/**
 * Web app manifest — Next metadata route, served at /manifest.webmanifest and
 * auto-linked from every page. Minimal installability hygiene only: no service
 * worker / offline (that stays the native app's job). theme/background pull
 * from the shared design tokens so web + mobile brand chrome stay in sync.
 *
 * Icons live in /public/icons (stable paths); the browser-tab favicon and iOS
 * apple-touch-icon come separately from app/icon.png + app/apple-icon.png.
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'BiteWorthy',
    short_name: 'BiteWorthy',
    description:
      'A pocket food filter for allergies, intolerances, and dietary needs. Find what you can eat at any restaurant.',
    start_url: '/',
    display: 'standalone',
    background_color: colors.bg,
    theme_color: colors.bite,
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
    ],
  };
}
