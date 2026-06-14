import type { Metadata } from 'next';
import type { ReactElement, ReactNode } from 'react';
import { PostHogProvider } from './_PostHogProvider';
import './globals.css';

export const metadata: Metadata = {
  title: 'BiteWorthy — Scan any menu, see only what you can eat',
  description:
    'A pocket food filter for allergies, intolerances, and dietary needs. Find what you can eat at any restaurant.',
};

// Explicit return type prevents tsc from referencing the pnpm-symlinked
// @types/react path, which triggers TS2742 in a workspace with both
// React 18 (mobile) and React 19 (web) hoisted.
export default function RootLayout({ children }: { children: ReactNode }): ReactElement {
  return (
    <html lang="en">
      <body className="bg-white text-zinc-900 antialiased">
        <PostHogProvider>{children}</PostHogProvider>
        <SiteDisclaimer />
      </body>
    </html>
  );
}

/**
 * Slim, site-wide legal disclaimer shown on every page. A plain-language
 * "at your own risk" line keeps the AS-IS / not-a-guarantee message in
 * front of users everywhere, not only on the Terms page.
 */
function SiteDisclaimer(): ReactElement {
  return (
    <footer
      role="contentinfo"
      data-testid="site-disclaimer"
      className="border-t border-zinc-200 px-6 py-4 text-center text-xs text-zinc-500"
    >
      BiteWorthy is a planning aid, not a guarantee — dietary info can be wrong or out of date, so
      always confirm with the restaurant. Use at your own risk. See our{' '}
      <a href="/terms" className="underline hover:text-zinc-700">
        Terms
      </a>{' '}
      and{' '}
      <a href="/privacy" className="underline hover:text-zinc-700">
        Privacy Policy
      </a>
      .
    </footer>
  );
}
