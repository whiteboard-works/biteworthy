import type { Metadata } from 'next';
import type { ReactElement, ReactNode } from 'react';
import { CURRENT_VERSION } from '@biteworthy/version-history';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * The BiteWorthy story — the user-facing version of `docs/vision.md`.
 *
 * Pure SSR, Tailwind only, same `bite` / `bw-*` tokens as the landing.
 * Voice is warm and plain — this is the page you send someone to explain
 * *why* the app exists, not how it works. The product principle ("safety
 * filters, taste ranks; always show why") is the spine.
 *
 * Copy uses real typographic glyphs (’ “ ” — …) rather than HTML
 * entities; the curly characters aren't ASCII, so they don't trip
 * `react/no-unescaped-entities`.
 */

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLegalMetadata({
  pageTitle: 'Our story',
  description:
    'Why BiteWorthy exists: a pocket food filter that gives people with allergies, celiac, and every other dietary need back the freedom to walk into a restaurant and just eat.',
  path: '/story',
  siteUrl: SITE_URL,
});

export default function StoryPage(): ReactElement {
  return (
    <main className="bg-white">
      <Hero />
      <Problem />
      <Inversion />
      <Principle />
      <Trust />
      <Crowd />
      <Durango />
      <Horizon />
      <ClosingCTA />
      <Footer />
    </main>
  );
}

function Hero(): ReactElement {
  return (
    <section className="mx-auto max-w-3xl px-bw-6 pt-bw-16 pb-bw-10">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Our story</p>
      <h1
        data-testid="story-headline"
        className="mt-bw-3 text-bw-3xl font-bold leading-[1.1] text-zinc-900 md:text-bw-4xl"
      >
        Eating out shouldn’t take a leap of faith.
      </h1>
      <p className="mt-bw-6 text-bw-lg text-zinc-700">
        For about a third of us, a menu isn’t a list of choices. It’s a wall of text hiding the two
        or three things we can actually eat — and the quiet work of finding them falls on us, every
        single time.
      </p>
      <p className="mt-bw-4 text-bw-lg text-zinc-700">
        BiteWorthy is a pocket food filter that flips the menu around: scan it, and see only what’s
        yours.
      </p>
    </section>
  );
}

function Problem(): ReactElement {
  return (
    <Section eyebrow="The problem" title="The menu wasn’t built for you.">
      <p>
        If you have celiac, a food allergy, an intolerance, a religious practice, or a way of
        eating you’ve chosen, you already know the routine: scan the menu twice, quietly interrogate
        the server, google the place in the parking lot, and hope. Sometimes it’s an awkward
        conversation. Sometimes it’s the social cost of being “the difficult one.” And sometimes —
        for the celiac, the severely allergic — it’s a real medical gamble.
      </p>
      <p>
        That work never shows up on the bill. But it’s the reason so many people order the same safe
        thing every time, or just stay home.
      </p>
    </Section>
  );
}

function Inversion(): ReactElement {
  return (
    <Section eyebrow="The idea" title="So we turned the menu inside out.">
      <p>
        Point your phone at any menu — the laminated one on the table, a PDF, a photo, a link. A few
        seconds later you’re looking at the same menu, rewritten for you: the dishes you can eat,
        front and center, and the ones you can’t, set aside.
      </p>
      <p>
        No chains-only database. No waiting for a restaurant to fill out a form. If a place isn’t
        listed yet, you scan it — and now it exists for the next person who eats the way you do.
      </p>
    </Section>
  );
}

function Principle(): ReactElement {
  return (
    <section className="bg-bite-light/30 px-bw-6 py-bw-16">
      <div className="mx-auto max-w-3xl">
        <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">What we believe</p>
        <blockquote
          data-testid="story-principle"
          className="mt-bw-4 border-l-4 border-bite pl-bw-5 text-bw-2xl font-bold leading-snug text-zinc-900"
        >
          Safety filters. Taste ranks.
        </blockquote>
        <div className="mt-bw-6 space-y-bw-4 text-bw-base text-zinc-700">
          <p>
            These are two different questions, and we never let them blur.{' '}
            <span className="font-semibold text-zinc-900">Can I eat this?</span> is about safety —
            it’s honest and absolute, and it decides what’s shown and what’s hidden.{' '}
            <span className="font-semibold text-zinc-900">Will I love this?</span> is about taste —
            it only changes the order, lifting your likely favorites to the top.
          </p>
          <p>
            Taste never hides a safe dish. Safety never gets softened into a suggestion. Mixing up
            “you might not enjoy this” with “this could hurt you” is the one mistake we refuse to
            make.
          </p>
        </div>
      </div>
    </section>
  );
}

function Trust(): ReactElement {
  return (
    <Section eyebrow="Why you can trust it" title="Every hidden dish tells you why.">
      <p>
        BiteWorthy never just says “no.” A hidden item always shows its reason —{' '}
        <span className="italic">“Contains dairy (cheese)”</span> — so you’re never guessing, and
        you can overrule us for a single meal if you know better.
      </p>
      <p>
        Behind each call is a confidence level and a source: was this confirmed by a person, read by
        AI, or set by the restaurant itself? Turn on{' '}
        <span className="font-semibold text-zinc-900">strict mode</span> and you’ll only see dishes
        that are fully confirmed — the setting we built for the people for whom a mistake means the
        ER.
      </p>
    </Section>
  );
}

function Crowd(): ReactElement {
  return (
    <Section eyebrow="Built together" title="Every scan helps the next person.">
      <p>
        The map of what’s safe to eat doesn’t exist anywhere — menus live as photos and PDFs nobody
        keeps current. So we’re building it together. Anyone can scan a menu and verify it, and that
        work quietly improves the app for the next diner with the same allergy.
      </p>
      <p>
        Community-added details start as{' '}
        <span className="font-semibold text-zinc-900">suggested</span> and stay invisible to
        strict-mode users until a human confirms them — so contributing is an act of care, and the
        people who most need certainty stay protected.
      </p>
    </Section>
  );
}

function Durango(): ReactElement {
  return (
    <Section eyebrow="Where we’re starting" title="Durango first. On purpose.">
      <p>
        We’re seeding the launch with independent Durango restaurants — real local places, not
        chains, not delivery apps. A small town with a finite set of menus is exactly where a tool
        like this can become genuinely complete, and where word travels.
      </p>
      <p>Other towns follow, once Durango proves the model.</p>
    </Section>
  );
}

function Horizon(): ReactElement {
  return (
    <Section eyebrow="Where it’s going" title="Toward a simple question, always answered.">
      <p>
        Picture walking down a street and seeing, at a glance, which few of the forty places around
        you are both safe <span className="italic">and</span> something you’d love. Picture pointing
        your phone at a menu in a language you don’t read, in a city you’ve never visited, and
        getting a safe, ranked answer anyway.
      </p>
      <p>
        That’s the whole point. Not more time on your phone — less. The question{' '}
        <span className="font-semibold text-zinc-900">“can I eat here?”</span> answered before you
        even have to ask.
      </p>
    </Section>
  );
}

function ClosingCTA(): ReactElement {
  return (
    <section className="mx-auto max-w-3xl px-bw-6 py-bw-16 text-center">
      <h2 className="text-bw-2xl font-bold text-zinc-900">Try it on your next meal out.</h2>
      <p className="mx-auto mt-bw-3 max-w-xl text-bw-base text-zinc-700">
        Six taps to a working profile. Free during the Durango beta — no ads, no email until you
        choose to save a profile.
      </p>
      <div className="mt-bw-8 flex flex-wrap justify-center gap-bw-3">
        <a
          href="/onboarding"
          data-testid="story-cta"
          className="rounded-bw-md bg-bite px-bw-6 py-bw-3 text-bw-base font-bold text-white shadow-sm hover:bg-bite-dark"
        >
          Try the web app →
        </a>
        <a
          href="/"
          className="rounded-bw-md border border-zinc-200 bg-white px-bw-6 py-bw-3 text-bw-base font-semibold text-zinc-700 hover:border-zinc-300"
        >
          Back to home
        </a>
      </div>
    </section>
  );
}

function Footer(): ReactElement {
  return (
    <footer className="border-t border-zinc-200 bg-zinc-50 px-bw-6 py-bw-12">
      <div className="mx-auto flex max-w-3xl flex-col gap-bw-3 text-bw-sm text-zinc-500 md:flex-row md:items-center md:justify-between">
        <p>
          © {new Date().getFullYear()} BiteWorthy · Made in Durango, CO. ·{' '}
          <a href="/updates" data-testid="footer-version" className="hover:text-zinc-700">
            v{CURRENT_VERSION}
          </a>
        </p>
        <nav className="flex flex-wrap gap-bw-4">
          <a href="/" className="hover:text-zinc-700">
            Home
          </a>
          <a href="/privacy" className="hover:text-zinc-700">
            Privacy
          </a>
          <a href="/terms" className="hover:text-zinc-700">
            Terms
          </a>
        </nav>
      </div>
    </footer>
  );
}

// ── Shared section block ────────────────────────────────────────────

function Section({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string;
  title: string;
  children: ReactNode;
}): ReactElement {
  return (
    <section className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">{eyebrow}</p>
      <h2 className="mt-bw-3 text-bw-2xl font-bold text-zinc-900">{title}</h2>
      <div className="mt-bw-4 space-y-bw-4 text-bw-base text-zinc-700">{children}</div>
    </section>
  );
}
