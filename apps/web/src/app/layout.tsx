import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'BiteWorthy — Scan any menu, see only what you can eat',
  description:
    'A pocket food filter for allergies, intolerances, and dietary needs. Find what you can eat at any restaurant.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-white text-zinc-900 antialiased">{children}</body>
    </html>
  );
}
