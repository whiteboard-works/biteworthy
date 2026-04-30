import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * Phase 5.9 — terms of service template.
 *
 * **DRAFT — needs lawyer review before App Store submission.**
 *
 * Resolves the Phase 5.5 marketing landing footer's `/terms`
 * placeholder href.
 */

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLegalMetadata({
  pageTitle: 'Terms of Service',
  description:
    'Acceptable use, content ownership, restaurant claims, and the limits of how much we can promise about a third-party menu being safe for you.',
  path: '/terms',
  siteUrl: SITE_URL,
});

const LAST_UPDATED = '2026-04-30';

export default function TermsPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Legal</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">
        Terms of Service
      </h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">Last updated: {LAST_UPDATED}</p>

      <DraftBanner />

      <article className="prose prose-zinc mt-bw-8 max-w-none text-zinc-800">
        <Section title="The bargain">
          <p>
            BiteWorthy is a free dietary filter for restaurant menus. By using it you agree to use
            it in good faith and to understand what it can and can&rsquo;t promise (see &ldquo;The
            allergen disclaimer&rdquo; below). If those don&rsquo;t work for you, please don&rsquo;t
            use the service.
          </p>
        </Section>

        <Section title="The allergen disclaimer">
          <p>
            <strong>BiteWorthy is a planning tool, not a medical device.</strong> We use AI to read
            menus and apply your dietary filter. AI gets things wrong. Restaurants change their
            recipes without telling us. Cross-contamination in the kitchen is invisible to any
            menu-text source.
          </p>
          <ul>
            <li>
              Always confirm with the restaurant before ordering anything that triggers a serious
              allergy.
            </li>
            <li>
              The &ldquo;hidden — contains dairy (cheese)&rdquo; chip is our best guess. The
              &ldquo;visible&rdquo; chip is also our best guess.
            </li>
            <li>
              We do not recommend BiteWorthy as the sole tool for managing anaphylactic allergies.
              Carry your prescribed treatment.
            </li>
          </ul>
        </Section>

        <Section title="Content you submit">
          <ul>
            <li>
              <strong>Reviews:</strong> you keep ownership; you grant BiteWorthy a license to host +
              display them on the platform. We may hide reviews that trip the moderation heuristics
              (Phase 4.6).
            </li>
            <li>
              <strong>Suggested edits</strong> (Phase 4.10): you grant BiteWorthy a license to merge
              accepted suggestions into the underlying ingredient and tag rows. The merge is
              attributed to your handle when accepted.
            </li>
            <li>
              <strong>Photos:</strong> you grant BiteWorthy a license to display them alongside the
              dish or restaurant. Don&rsquo;t upload anything you don&rsquo;t have rights to.
            </li>
          </ul>
        </Section>

        <Section title="Restaurant claims">
          <p>
            Phase 4.9&rsquo;s claim flow lets a restaurant owner verify ownership via a domain-email
            check. Once verified, the owner can edit menu items and respond to reviews. Verifying
            doesn&rsquo;t grant the owner the right to delete unfavorable reviews — moderation
            still goes through the queue.
          </p>
        </Section>

        <Section title="Acceptable use">
          <ul>
            <li>No spam, abuse, harassment, or bot-driven submissions.</li>
            <li>Don&rsquo;t scrape the API at a rate that affects other users.</li>
            <li>
              Don&rsquo;t pretend to be a restaurant owner you&rsquo;re not. The claim flow exists
              for a reason.
            </li>
            <li>
              Don&rsquo;t upload menu images you don&rsquo;t have permission to share. Most public
              menus are fine; some restaurants explicitly forbid republication.
            </li>
          </ul>
        </Section>

        <Section title="Analytics" id="analytics">
          <p>
            On web, BiteWorthy uses PostHog for funnel analytics (anonymous events like{' '}
            <em>app_open</em>, <em>menu_filtered</em>; never review text or profile fields). We
            honor browser <em>Do-Not-Track</em> automatically and a per-user opt-out at{' '}
            <em>/profile/settings</em>.
          </p>
          <p>
            On mobile, analytics are <strong>off by default</strong>. They only fire if you
            explicitly enable them in <em>Settings → Analytics</em>. The App Store privacy
            questionnaire reflects this.
          </p>
        </Section>

        <Section title="Termination">
          <p>
            You can delete your account at any time (see <a href="/privacy">Privacy Policy</a>). We
            can suspend accounts that violate these terms; we&rsquo;ll explain why if it happens.
          </p>
        </Section>

        <Section title="Governing law">
          <p>
            These terms are governed by the laws of the State of Colorado, USA. Disputes go to the
            state or federal courts located in La Plata County, Colorado.
          </p>
        </Section>

        <Section title="Contact">
          <p>
            <a href="mailto:hello@bite-worthy.com">hello@bite-worthy.com</a> for anything in these
            terms. Legal notices to{' '}
            <a href="mailto:legal@bite-worthy.com">legal@bite-worthy.com</a>.
          </p>
        </Section>
      </article>
    </main>
  );
}

function DraftBanner(): ReactElement {
  return (
    <div
      role="note"
      className="mt-bw-6 rounded-bw-md border border-warn/40 bg-warn/10 p-bw-4 text-bw-sm text-zinc-800"
      data-testid="draft-banner"
    >
      <strong>Draft.</strong> Has not yet had final lawyer review; the launch checklist (Phase 5.9)
      requires that pass before App Store / Play Store submission.
    </div>
  );
}

function Section({
  title,
  id,
  children,
}: {
  title: string;
  id?: string;
  children: ReactElement | ReactElement[];
}): ReactElement {
  return (
    <section className="mt-bw-8" id={id}>
      <h2 className="text-bw-xl font-bold text-zinc-900">{title}</h2>
      <div className="mt-bw-3">{children}</div>
    </section>
  );
}
