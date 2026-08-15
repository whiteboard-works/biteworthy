import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { DURANGO_DIET_SLUGS, humanizeDietSlug } from '../../lib/durango';

/**
 * Index for the `/durango/<diet>` SEO pages. Until now `/durango` 404'd
 * — every diet page existed but only the sitemap knew, so a user
 * trimming the URL (or any internal link wanting "browse by diet") had
 * nowhere to land. Pure SSR, static: the curated slug list is the same
 * hard-coded one the diet pages pre-render from.
 */

const title = 'Dietary guides for Durango — BiteWorthy';
const description =
  'Durango restaurants ranked for celiac, vegan, allergies, and more — pick your diet and see who has the most dishes you can actually eat.';

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: '/durango' },
  openGraph: { title, description, type: 'website', url: '/durango' },
  twitter: { card: 'summary_large_image', title, description },
};

export default function DurangoIndexPage(): ReactElement {
  return (
    <main className="bg-white">
      <section className="mx-auto max-w-4xl px-bw-6 pt-bw-16 pb-bw-16">
        <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">
          Durango, Colorado
        </p>
        <h1 className="mt-bw-3 text-bw-3xl font-bold leading-tight text-zinc-900 md:text-bw-4xl">
          Where can you eat in Durango?
        </h1>
        <p className="mt-bw-4 max-w-2xl text-bw-base text-zinc-700">
          Pick your diet — each guide ranks Durango restaurants by how many menu items pass
          that filter, with every hidden dish explaining why.
        </p>

        <ul className="mt-bw-8 grid gap-bw-3 sm:grid-cols-2" data-testid="diet-index">
          {DURANGO_DIET_SLUGS.map((slug) => (
            <li key={slug}>
              <a
                href={`/durango/${slug}`}
                data-testid={`diet-link-${slug}`}
                className="block rounded-bw-lg border border-zinc-200 bg-white p-bw-4 shadow-sm hover:border-bite"
              >
                <span className="text-bw-lg font-bold text-zinc-900">
                  {humanizeDietSlug(slug)}
                </span>
                <span className="mt-bw-1 block text-bw-sm text-zinc-600">
                  {humanizeDietSlug(slug)} restaurants in Durango →
                </span>
              </a>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
