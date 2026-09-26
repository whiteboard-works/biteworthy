import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLandingMetadata } from '../lib/landing-meta';
import { fetchRestaurants, type RestaurantSummary } from '../lib/restaurants';
import { FeatureRow } from './_FeatureRow';
import { Footer } from './_Footer';
import { HeroCta, MarketingExtras, TryADiet } from './_HeroCta';
import { RestaurantCards } from './_RestaurantCards';
import { WaitlistSection } from './_waitlist-form';

// ISR: keep the landing static + fast, but let the live restaurant list
// refresh every 5 minutes as menus get published.
export const revalidate = 300;

/**
 * Phase 5.5 — marketing landing.
 *
 * Pure SSR. No client components. Tailwind only — colors flow from
 * `@biteworthy/ui-tokens` via `tailwind.config.ts`'s extended palette
 * (`bite`, `bite-light`, `bite-dark`).
 *
 * The structure is deliberately conservative:
 *
 *   1. Hero — value prop in one sentence + subhead + CTAs.
 *   2. Three-up — "Scan", "Pick filter", "See safe dishes."
 *   3. Local-first note — Durango is the launch market.
 *   4. Footer — privacy / terms (placeholders until 5.9), GitHub.
 *
 * App Store + Play Store CTAs render as "Coming soon" badges until
 * Phase 5.9 lands the real store URLs. "Try the web app" deep-links
 * straight to /onboarding so a curious visitor lands in the
 * profile-creation flow — the existing 6-tap path from Phase 3.2 +
 * 3.8 takes over from there.
 *
 * "Value before signup" — that onboarding CTA is now secondary. The
 * primary hero action is `TryADiet`: diet chips linking straight to
 * the zero-signup, already-filtered `/durango/<diet>` pages, so a
 * signed-out visitor sees a real filtered menu before ever making an
 * account.
 */

const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLandingMetadata({ siteUrl: SITE_URL });

export default function HomePage(): ReactElement {
  return (
    <main className="bg-white">
      <Hero />
      <BrowseRestaurants />
      <FeatureRow />
      <DurangoNote />
      <Footer />
    </main>
  );
}

async function BrowseRestaurants(): Promise<ReactElement> {
  let restaurants: RestaurantSummary[] = [];
  try {
    restaurants = await fetchRestaurants({ revalidate: 300 });
  } catch {
    // API hiccup — show the empty state, never break the landing page.
  }

  return (
    <section className="mx-auto max-w-5xl px-bw-6 py-bw-16">
      <div className="flex flex-wrap items-end justify-between gap-bw-3">
        <h2 className="text-bw-2xl font-bold text-zinc-900">Menus you can filter right now</h2>
        {restaurants.length > 0 && (
          <a
            href="/restaurants"
            data-testid="home-browse-all"
            className="text-bw-sm font-bold text-bite hover:text-bite-dark"
          >
            Browse all restaurants →
          </a>
        )}
      </div>

      {restaurants.length === 0 ? (
        <div className="mt-bw-4 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-6 text-bw-base text-zinc-600">
          We&rsquo;re adding Durango menus now.
        </div>
      ) : (
        <div className="mt-bw-6">
          <RestaurantCards restaurants={restaurants.slice(0, 6)} />
        </div>
      )}
    </section>
  );
}

function Hero(): ReactElement {
  return (
    <section className="mx-auto max-w-4xl px-bw-6 pt-bw-16 pb-bw-12 md:pt-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">BiteWorthy</p>
      <h1 className="mt-bw-3 text-bw-4xl font-bold leading-[1.05] text-zinc-900 md:text-[56px]">
        Scan any menu,
        <br />
        see only what you can eat.
      </h1>
      <p className="mt-bw-6 max-w-2xl text-bw-lg text-zinc-700">
        A pocket food filter for celiac, allergies, vegan, and every other dietary need.
        Snap a photo of a menu — or paste a link — and BiteWorthy hides the dishes that
        aren&rsquo;t safe for you. With <span className="font-bold">why</span>, every time.
      </p>

      {/* "Value before signup" — the zero-commitment path comes first, the
          signup CTA is secondary. A signed-out visitor can see a real,
          filtered Durango menu before ever making an account. */}
      <div className="mt-bw-8">
        <TryADiet />
      </div>

      <div className="mt-bw-6 flex flex-wrap items-center gap-bw-3">
        <HeroCta />
        <MarketingExtras />
      </div>

      <p className="mt-bw-4">
        <a
          href="/story"
          data-testid="hero-story"
          className="text-bw-base font-bold text-bite hover:text-bite-dark"
        >
          Read our story →
        </a>
      </p>

      <p className="mt-bw-4 text-bw-xs text-zinc-500">
        Free during the Durango beta. No ads, no email signup until you choose to save a profile.
      </p>

      <WaitlistSection />
    </section>
  );
}

function DurangoNote(): ReactElement {
  return (
    <section className="mx-auto max-w-3xl px-bw-6 py-bw-16 text-center">
      <h2 className="text-bw-2xl font-bold text-zinc-900">Built for Durango first.</h2>
      <p className="mt-bw-3 text-bw-base text-zinc-700">
        We&rsquo;re adding independent Durango restaurants — not chains, not delivery apps. If you
        live here and want a place added, the app has a one-tap &ldquo;suggest a restaurant&rdquo;
        flow that goes straight to the contributor queue.
      </p>
      <p className="mt-bw-4 text-bw-sm text-zinc-500">
        Other towns next, once Durango proves the model.
      </p>
    </section>
  );
}
