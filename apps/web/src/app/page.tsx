import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLandingMetadata } from '../lib/landing-meta';
import { fetchRestaurants, type RestaurantSummary } from '../lib/restaurants';
import { HeroCta } from './_HeroCta';
import { RestaurantCards } from './_RestaurantCards';
import WaitlistForm from './_waitlist-form';

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
          We&rsquo;re adding Durango menus now. Know a spot that isn&rsquo;t here?{' '}
          <a href="/ingest" className="font-bold text-bite hover:text-bite-dark">
            Scan its menu →
          </a>
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

      <div className="mt-bw-8 flex flex-wrap gap-bw-3">
        <HeroCta />
        <ComingSoonBadge label="iOS app" />
        <ComingSoonBadge label="Android app" />
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

      <div className="mt-bw-8 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-4">
        <p className="text-bw-sm font-bold text-zinc-900">Want a heads-up when the apps drop?</p>
        <p className="mt-bw-1 text-bw-sm text-zinc-600">
          One email, 48 hours before public release. Nothing else.
        </p>
        <WaitlistForm />
      </div>
    </section>
  );
}

function FeatureRow(): ReactElement {
  const features: { title: string; body: string; emoji: string }[] = [
    {
      emoji: '📸',
      title: 'Scan the menu',
      body: 'Camera, photo library, or paste a link to a PDF / online menu. Multi-page menus are fine — the AI reads each page in seconds.',
    },
    {
      emoji: '🥗',
      title: 'Pick your filter',
      body: 'Six taps to a working profile. Pick a preset (Celiac, Tree Nut, Vegan, Diabetes-friendly, …) or build your own avoid list.',
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
        {features.map((f) => (
          <article key={f.title} className="rounded-bw-lg bg-white p-bw-6 shadow-sm">
            <p aria-hidden className="text-bw-2xl">
              {f.emoji}
            </p>
            <h2 className="mt-bw-3 text-bw-xl font-bold text-zinc-900">{f.title}</h2>
            <p className="mt-bw-2 text-bw-base text-zinc-700">{f.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function DurangoNote(): ReactElement {
  return (
    <section className="mx-auto max-w-3xl px-bw-6 py-bw-16 text-center">
      <h2 className="text-bw-2xl font-bold text-zinc-900">Built for Durango first.</h2>
      <p className="mt-bw-3 text-bw-base text-zinc-700">
        We&rsquo;re seeding the launch with 30 independent Durango restaurants — not chains, not
        delivery apps. If you live here and want a place added, the app has a one-tap
        &ldquo;suggest a restaurant&rdquo; flow that goes straight to the contributor queue.
      </p>
      <p className="mt-bw-4 text-bw-sm text-zinc-500">
        Other towns next, once Durango proves the model.
      </p>
    </section>
  );
}

function Footer(): ReactElement {
  return (
    <footer className="border-t border-zinc-200 bg-zinc-50 px-bw-6 py-bw-12">
      <div className="mx-auto flex max-w-5xl flex-col gap-bw-3 text-bw-sm text-zinc-500 md:flex-row md:items-center md:justify-between">
        <p>
          &copy; {new Date().getFullYear()} BiteWorthy &middot; Made in Durango, CO.
        </p>
        <nav className="flex flex-wrap gap-bw-4">
          <a href="/restaurants" className="hover:text-zinc-700" data-testid="footer-restaurants">
            Restaurants
          </a>
          <a href="/story" className="hover:text-zinc-700" data-testid="footer-story">
            Our story
          </a>
          <a href="/privacy" className="hover:text-zinc-700" data-testid="footer-privacy">
            Privacy
          </a>
          <a href="/terms" className="hover:text-zinc-700" data-testid="footer-terms">
            Terms
          </a>
          <a href="/press" className="hover:text-zinc-700" data-testid="footer-press">
            Press
          </a>
          <a
            href="https://github.com/whiteboard-works/biteworthy"
            className="hover:text-zinc-700"
            data-testid="footer-github"
          >
            GitHub
          </a>
        </nav>
      </div>
    </footer>
  );
}

function ComingSoonBadge({ label }: { label: string }): ReactElement {
  return (
    <span
      data-testid={`cta-soon-${label.toLowerCase().replace(/\s+/g, '-')}`}
      className="inline-flex items-center gap-bw-2 rounded-bw-md border border-zinc-200 bg-zinc-50 px-bw-4 py-bw-3 text-bw-base font-semibold text-zinc-500"
    >
      {label}
      <span className="rounded-bw-pill bg-zinc-200 px-bw-2 py-bw-0_5 text-bw-xs uppercase tracking-wider">
        Coming soon
      </span>
    </span>
  );
}
