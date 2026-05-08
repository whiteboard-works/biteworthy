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
      </body>
    </html>
  );
}
