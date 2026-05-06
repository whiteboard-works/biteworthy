import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * Phase 5.10 — press kit page.
 *
 * One-page resource for journalists + bloggers covering the launch.
 * Pure SSR. Logo files (PNG + SVG) live at `/logo-*.png|svg` in
 * `apps/web/public/` once Phase 5.9-wiring renders them; the page
 * references them by URL today + degrades gracefully (broken-image
 * placeholders) until they exist.
 */

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLegalMetadata({
  pageTitle: 'Press kit',
  description:
    'Logo, screenshots, founder bio, blurbs, and contact for press covering the BiteWorthy Durango launch.',
  path: '/press',
  siteUrl: SITE_URL,
});

export default function PressPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Press</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">Press kit</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">
        For journalists, bloggers, and outlets covering the BiteWorthy Durango launch.
      </p>

      <Section title="One-line">
        <p className="text-bw-lg text-zinc-800">
          BiteWorthy is a pocket food filter for celiac, allergies, vegan, and every other dietary
          need &mdash; scan any restaurant menu, see only the dishes you can actually eat.
        </p>
      </Section>

      <Section title="50 words">
        <p className="text-bw-base text-zinc-800">
          BiteWorthy is a free dietary filter for restaurant menus. Pick a preset (Celiac, Tree
          Nut, Vegan, &hellip;) or build your own avoid list. Scan a menu with the camera or paste
          a link. Hidden dishes each say <em>why</em>. Built for independent restaurants, launched
          in Durango, Colorado.
        </p>
      </Section>

      <Section title="200 words">
        <p className="text-bw-base text-zinc-800">
          BiteWorthy turns the question &ldquo;is there anything I can eat here?&rdquo; into a
          glanceable answer. The app reads any restaurant menu &mdash; from a phone-camera scan, a
          PDF, or an online link &mdash; and applies a dietary filter you set in six taps. Items
          you can&rsquo;t eat get hidden, with a transparent label explaining
          <em> why</em> (&ldquo;Contains dairy (cheese)&rdquo;, &ldquo;Contains gluten
          (wheat)&rdquo;). Tap &ldquo;show anyway&rdquo; to override one for tonight; flag
          &ldquo;never hide this dish&rdquo; to teach the filter your nuance.
        </p>
        <p className="mt-bw-3 text-bw-base text-zinc-800">
          The launch beta seeds 30 independent Durango restaurants &mdash; not chains, not
          delivery aggregators. Reviews are by real diners with the same dietary needs as you;
          owners can claim their listings to fix mistakes; everyone can suggest fixes through a
          community moderation queue. Free, no ads, opt-in analytics. Built in Durango, Colorado,
          with the same dietary-filter logic running identically on web and mobile.
        </p>
      </Section>

      <Section title="Logo + screenshots">
        <p className="text-bw-sm text-zinc-700">
          High-res logo files + marketing screenshots (per device class) ship via Phase 5.9-wiring.
          Until then, contact <a href="mailto:press@bite-worthy.com">press@bite-worthy.com</a> for
          assets.
        </p>
        <ul className="mt-bw-3 list-disc pl-bw-6 text-bw-sm text-zinc-700">
          <li>
            <a href="/logo.svg" data-testid="press-logo-svg">Logo &mdash; SVG</a>
            {' '}(coming with Phase 5.9-wiring)
          </li>
          <li>
            <a href="/logo.png" data-testid="press-logo-png">Logo &mdash; PNG (1024&times;1024)</a>
            {' '}(coming with Phase 5.9-wiring)
          </li>
          <li>App Store + Play Store listing copy lives in
            {' '}<code>apps/mobile/store-listing/</code> (open-source, see GitHub).
          </li>
        </ul>
      </Section>

      <Section title="Founder">
        <p className="text-bw-base text-zinc-800">
          Skylar Bolton &mdash; software engineer based in Durango, Colorado.
          {' '}<a href="https://github.com/whiteboard-works" className="underline">Whiteboard Works</a>.
        </p>
      </Section>

      <Section title="Contact">
        <p className="text-bw-base text-zinc-800">
          Press inquiries: <a href="mailto:press@bite-worthy.com">press@bite-worthy.com</a>.
          {' '}General: <a href="mailto:hello@bite-worthy.com">hello@bite-worthy.com</a>.
        </p>
      </Section>
    </main>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: ReactElement | ReactElement[];
}): ReactElement {
  return (
    <section className="mt-bw-8">
      <h2 className="text-bw-xl font-bold text-zinc-900">{title}</h2>
      <div className="mt-bw-3">{children}</div>
    </section>
  );
}
