/**
 * Phase 5.9 — metadata composition for the legal pages
 * (`/privacy`, `/terms`). Pure-TS so the title / description /
 * canonical / OG strings are unit-testable without spinning up
 * Next.
 */

import type { Metadata } from 'next';

export interface LegalPageInput {
  /** "Privacy Policy" or "Terms of Service" — used as the page title prefix. */
  pageTitle: string;
  /** One-sentence SEO description. */
  description: string;
  /** Path under the site, e.g. "/privacy". */
  path: string;
  /** Public canonical origin (defaults to NEXT_PUBLIC_SITE_URL at the call site). */
  siteUrl: string;
}

export function buildLegalMetadata({
  pageTitle,
  description,
  path,
  siteUrl,
}: LegalPageInput): Metadata {
  const base = siteUrl.replace(/\/+$/, '');
  const fullTitle = `${pageTitle} — BiteWorthy`;
  return {
    title: fullTitle,
    description,
    metadataBase: new URL(base),
    alternates: { canonical: path },
    openGraph: {
      title: fullTitle,
      description,
      url: `${base}${path}`,
      type: 'article',
      siteName: 'BiteWorthy',
    },
    twitter: {
      card: 'summary',
      title: fullTitle,
      description,
    },
    // Legal pages are stable; tell crawlers to index but not to weight
    // them as "fresh" content above the funnel pages.
    robots: { index: true, follow: true },
  };
}
