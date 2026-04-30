/**
 * Phase 5.5 — marketing landing metadata composition.
 *
 * Pure-TS helper so the title / description / Open Graph / Twitter
 * card strings can be unit-tested without touching Next. The
 * landing's `metadata` export wraps this.
 */

import type { Metadata } from 'next';

export interface LandingMetaInput {
  /**
   * Public canonical origin. In prod: `https://bite-worthy.com`. In
   * preview / dev: whatever Vercel emits (`NEXT_PUBLIC_SITE_URL`).
   */
  siteUrl: string;
}

const TITLE = 'BiteWorthy — Scan any menu, see only what you can eat';
const DESCRIPTION =
  'A pocket food filter for celiac, allergies, vegan, and any other dietary need. Scan any restaurant menu, see only the dishes you can actually eat. Independent restaurants, not just chains.';

/** Built once per page render. Pure: same input → same output. */
export function buildLandingMetadata({ siteUrl }: LandingMetaInput): Metadata {
  const base = siteUrl.replace(/\/+$/, '');
  const ogImage = `${base}/og.png`;

  return {
    title: TITLE,
    description: DESCRIPTION,
    metadataBase: new URL(base),
    alternates: { canonical: '/' },
    openGraph: {
      title: TITLE,
      description: DESCRIPTION,
      url: base,
      siteName: 'BiteWorthy',
      type: 'website',
      images: [
        {
          url: ogImage,
          width: 1200,
          height: 630,
          alt: 'BiteWorthy — Scan any menu, see only what you can eat',
        },
      ],
    },
    twitter: {
      card: 'summary_large_image',
      title: TITLE,
      description: DESCRIPTION,
      images: [ogImage],
    },
  };
}
