import type { Route } from 'next';
import type { ReactElement } from 'react';
import Link from 'next/link';

/**
 * The landing page's three-up feature row. The 📸 scan tile links into
 * /chat — before this the headline feature was unreachable for an
 * anonymous visitor (finding 4, `docs/plans/ux-exploration-2026-08-15.md`):
 * both store CTAs say "coming soon" and the Chat nav link was hidden
 * until signed in. /chat itself bounces signed-out visitors through
 * /login?next=%2Fchat, so the tile can link unconditionally.
 */
export function FeatureRow(): ReactElement {
  const features: { title: string; body: string; emoji: string; href?: Route }[] = [
    {
      emoji: '📸',
      title: 'Scan the menu',
      body: 'Camera, photo library, or paste a link to a PDF / online menu. Multi-page menus are fine — the AI reads each page in seconds.',
      href: '/chat',
    },
    {
      emoji: '🥗',
      title: 'Pick your filter',
      body: 'Six taps to a working profile. Pick a preset (Celiac, Tree Nut, Vegan, Halal, …) or build your own avoid list.',
    },
    {
      emoji: '✓',
      title: 'See only safe dishes',
      body: 'Hidden items each say why — "Contains dairy (cheese)" — so you never wonder. Tap "show anyway" to override one for this meal.',
    },
  ];
  return (
    <section className="bg-bite-light/30 px-bw-6 py-bw-16">
      <div className="mx-auto grid max-w-5xl gap-bw-8 md:grid-cols-3">
        {features.map((f) => {
          const inner = (
            <>
              <p aria-hidden className="text-bw-2xl">
                {f.emoji}
              </p>
              <h2 className="mt-bw-3 text-bw-xl font-bold text-zinc-900">{f.title}</h2>
              <p className="mt-bw-2 text-bw-base text-zinc-700">{f.body}</p>
            </>
          );
          return f.href ? (
            <Link
              key={f.title}
              href={f.href}
              data-testid="feature-scan-link"
              className="rounded-bw-lg bg-white p-bw-6 shadow-sm transition-shadow hover:shadow-md"
            >
              {inner}
              <p className="mt-bw-3 text-bw-xs text-zinc-500">
                Free during the beta — sign in to start a scan →
              </p>
            </Link>
          ) : (
            <article key={f.title} className="rounded-bw-lg bg-white p-bw-6 shadow-sm">
              {inner}
            </article>
          );
        })}
      </div>
    </section>
  );
}
