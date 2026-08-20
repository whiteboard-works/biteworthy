import type { Metadata, Viewport } from 'next';
import type { ReactElement, ReactNode } from 'react';
import { colors } from '@biteworthy/ui-tokens';
import { PostHogProvider } from './_PostHogProvider';
import { SiteDisclaimer } from './_SiteDisclaimer';
import { SiteHeader } from './_SiteHeader';
import './globals.css';

export const metadata: Metadata = {
  title: 'BiteWorthy — Scan any menu, see only what you can eat',
  description:
    'A pocket food filter for allergies, intolerances, and dietary needs. Find what you can eat at any restaurant.',
  applicationName: 'BiteWorthy',
  // Standalone add-to-home-screen on iOS; the manifest covers Android/Chrome.
  appleWebApp: { capable: true, title: 'BiteWorthy', statusBarStyle: 'default' },
};

export const viewport: Viewport = {
  themeColor: colors.bite,
};

// Explicit return type prevents tsc from referencing the pnpm-symlinked
// @types/react path, which triggers TS2742 in a workspace with both
// React 18 (mobile) and React 19 (web) hoisted.
export default function RootLayout({ children }: { children: ReactNode }): ReactElement {
  return (
    <html lang="en">
      <body className="bg-white text-zinc-900 antialiased">
        <PostHogProvider>
          <SiteHeader />
          {children}
        </PostHogProvider>
        <SiteDisclaimer />
      </body>
    </html>
  );
}
