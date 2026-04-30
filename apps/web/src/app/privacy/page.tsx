import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * Phase 5.9 — privacy policy template.
 *
 * **DRAFT — needs lawyer review before App Store submission.**
 *
 * Fills the App Privacy disclosures with BiteWorthy's actual data
 * flows (Phases 1–5). The boilerplate sections (cookies, GDPR
 * rights, CCPA, contact) are written for what we DO collect; if a
 * lawyer adds collection paths we don't yet have, they update both
 * this page AND the App Store privacy questionnaire to match.
 *
 * Resolves the Phase 5.5 marketing landing footer's `/privacy`
 * placeholder href.
 */

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLegalMetadata({
  pageTitle: 'Privacy Policy',
  description:
    'How BiteWorthy handles user data: dietary profiles, review photos, restaurant visits, and the small list of third-party services we use.',
  path: '/privacy',
  siteUrl: SITE_URL,
});

const LAST_UPDATED = '2026-04-30';

export default function PrivacyPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Legal</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">
        Privacy Policy
      </h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">Last updated: {LAST_UPDATED}</p>

      <DraftBanner />

      <article className="prose prose-zinc mt-bw-8 max-w-none text-zinc-800">
        <Section title="The short version">
          <p>
            BiteWorthy keeps the data we need to make the dietary filter work and not much more.
            We don&rsquo;t sell your data. We don&rsquo;t share it with advertisers. The list of
            third-party services we use is short and named below.
          </p>
        </Section>

        <Section title="What we collect">
          <ul>
            <li>
              <strong>Account:</strong> email address, hashed password, OAuth identifier (if you
              sign in with Apple or Google), display handle. Optional photo.
            </li>
            <li>
              <strong>Dietary profile:</strong> the ingredients and tags you mark &ldquo;avoid,&rdquo;
              the dietary preset (e.g. <em>Celiac</em>) you picked, your strictness setting. Stored
              against your account so it follows you across devices.
            </li>
            <li>
              <strong>Reviews:</strong> the rating, body, and optional photo you submit on a dish.
              Photos are stored on Cloudflare R2 (see &ldquo;Where data lives&rdquo;).
            </li>
            <li>
              <strong>Restaurant visits:</strong> when you open a filtered restaurant page while
              signed in, we record one row per (user, restaurant, day) so you can find it again in{' '}
              <em>My filtered menus</em>. Anonymous browsing creates no such row.
            </li>
            <li>
              <strong>Suggested edits:</strong> if you submit a fix to a dish (e.g. &ldquo;this
              actually contains dairy&rdquo;), we keep the suggestion + its decision history for the
              moderation queue.
            </li>
          </ul>
        </Section>

        <Section title="What we do NOT collect">
          <ul>
            <li>Real name (unless you put it in your display handle).</li>
            <li>Phone number.</li>
            <li>Address or GPS coordinates.</li>
            <li>Device fingerprints, advertising IDs, or cross-app tracking signals.</li>
          </ul>
        </Section>

        <Section title="Where data lives">
          <ul>
            <li>
              <strong>Postgres on Fly.io</strong> (region: Denver, USA): your account, profile,
              reviews text, suggestions.
            </li>
            <li>
              <strong>Cloudflare R2</strong>: review photos and the cropped per-dish photos that the
              ingestion pipeline extracts from menu images.
            </li>
            <li>
              <strong>Anthropic</strong>: when a menu is being ingested, the menu image is sent to
              Anthropic Claude for OCR + structuring. The image leaves our servers but is not used
              to train the model. We do not send your reviews or profile to Anthropic.
            </li>
            <li>
              <strong>Postmark</strong>: outbound email (claim verification, password reset). The
              recipient address and message body pass through Postmark; we don&rsquo;t store the
              message itself.
            </li>
            <li>
              <strong>PostHog</strong> (optional, if you opt in): anonymous funnel events like{' '}
              <em>app_open</em>, <em>menu_filtered</em>. No content of reviews or profile fields is
              sent. See <a href="/terms#analytics">Terms § Analytics</a> for the opt-in flow.
            </li>
          </ul>
        </Section>

        <Section title="Your controls">
          <ul>
            <li>
              <strong>Export your data:</strong> email <a href="mailto:privacy@bite-worthy.com">privacy@bite-worthy.com</a>{' '}
              and we&rsquo;ll send a JSON archive within 30 days.
            </li>
            <li>
              <strong>Delete your account:</strong> same email, same response window. Reviews are
              anonymized (set to <em>removed_user</em>) by default; let us know if you want them
              hard-deleted instead.
            </li>
            <li>
              <strong>Opt out of analytics:</strong> on web, set the toggle in{' '}
              <em>/profile/settings</em>. On mobile, analytics are off by default — they only fire
              if you explicitly enable them in <em>Settings → Analytics</em>. We honor browser
              Do-Not-Track on the web side automatically.
            </li>
          </ul>
        </Section>

        <Section title="Children">
          <p>
            BiteWorthy is for adults — restaurants, allergens, dining out. If we learn we&rsquo;ve
            collected data from someone under 13, we delete it. (BiteWorthy is not directed at
            children.)
          </p>
        </Section>

        <Section title="Changes">
          <p>
            We&rsquo;ll update the date at the top when this page changes. Material changes get a
            highlighted note on the homepage and an email to active accounts.
          </p>
        </Section>

        <Section title="Contact">
          <p>
            <a href="mailto:privacy@bite-worthy.com">privacy@bite-worthy.com</a> for anything in
            this policy. Questions about specific data, takedowns, or legal requests.
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
      <strong>Draft.</strong> This template fills the App Privacy disclosures with BiteWorthy&rsquo;s
      actual data flows but has not yet had final lawyer review. The launch checklist (Phase 5.9)
      requires that pass before App Store / Play Store submission.
    </div>
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
