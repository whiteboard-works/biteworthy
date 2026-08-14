import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * Phase 5.9 — privacy policy template.
 *
 * **DRAFT — needs lawyer review before App Store submission.**
 *
 * Fills the App Privacy disclosures with BiteWorthy's actual data
 * flows (Phases 1–8). The boilerplate sections (retention, privacy
 * rights, children, contact) are written for what we DO collect; if a
 * lawyer adds collection paths we don't yet have, they update both
 * this page AND the App Store privacy questionnaire to match.
 *
 * Legal-remediation Phase 1 (see docs/plans/legal-remediation.md):
 * corrected hosting facts (Hetzner + Neon, not Fly.io), added
 * retention + CCPA-rights + public-information sections, disclosed the
 * waitlist and shareable-filter-link data flows, and made the
 * analytics and deletion wording match what the code actually does.
 *
 * The email subprocessor was corrected to Resend (PR #403 switched
 * production SMTP; this page still named Postmark). Naming the wrong
 * processor is the one drift here with legal weight, so the
 * LAST_UPDATED date moves with it.
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

const LAST_UPDATED = '2026-08-14';

export default function PrivacyPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Legal</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">Privacy Policy</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">Last updated: {LAST_UPDATED}</p>

      <DraftBanner />

      <article className="prose prose-zinc mt-bw-8 max-w-none text-zinc-800">
        <Section title="The short version">
          <p>
            BiteWorthy keeps the data we need to make the dietary filter work and not much more. We
            don’t sell or share your personal information. We don’t share it with advertisers. The
            list of third-party services we use is short and named below. You must be at least 13
            years old to use BiteWorthy.
          </p>
        </Section>

        <Section title="What we collect">
          <ul>
            <li>
              <strong>Account:</strong> email address, hashed password, OAuth identifier (if you
              sign in with Apple or Google), display handle. Optional photo.
            </li>
            <li>
              <strong>Dietary profile:</strong> the ingredients and tags you mark “avoid,” the
              dietary preset (e.g. <em>Celiac</em>) you picked, your strictness setting, and any
              taste signals (ingredients/tags you like or dislike) you add to improve your picks.
              Stored against your account so it follows you across devices.
            </li>
            <li>
              <strong>Reviews:</strong> the rating, body, and optional photo you submit on a dish.
              Reviews are public — see “What’s public” below. Photos are stored on Cloudflare R2
              (see “Where data lives”).
            </li>
            <li>
              <strong>Restaurant visits:</strong> when you open a filtered restaurant page while
              signed in, we record one row per (user, restaurant, day) so you can find it again in{' '}
              <em>My filtered menus</em>. Anonymous browsing creates no such row.
            </li>
            <li>
              <strong>Suggested edits:</strong> if you submit a fix to a dish (e.g. “this actually
              contains dairy”), we keep the suggestion + its decision history for the moderation
              queue.
            </li>
            <li>
              <strong>Waitlist:</strong> if you join the launch waitlist, we store your email
              address so we can tell you when BiteWorthy is available.
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

        <Section title="What's public">
          <p>
            Your reviews — the rating, text, and any photo — appear publicly next to your display
            handle on the dish page and on your profile at <em>/u/your-handle</em>. Your{' '}
            <strong>dietary profile is never shown publicly</strong>: what you avoid, your presets,
            your strictness, and your taste signals stay private to your account. Be aware that a
            pattern of public reviews can let someone infer your preferences.
          </p>
          <p>
            If you share a filtered menu link, the link itself encodes your avoid-lists and
            strictness so the recipient sees the same filter. It does not include your identity,
            email, or taste signals — but treat a shared link like any private link, since anyone
            who has it can read those filter settings.
          </p>
        </Section>

        <Section title="Where data lives">
          <ul>
            <li>
              <strong>Neon Postgres</strong> (AWS, US East): your account, profile, review text,
              suggestions, and visit history.
            </li>
            <li>
              <strong>Hetzner</strong> (Ashburn, USA): the servers that run the API.
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
              <strong>Resend</strong>: outbound email (claim verification, password reset). The
              recipient address and message body pass through Resend; we don’t store the message
              itself.
            </li>
            <li>
              <strong>PostHog</strong>: product analytics. See “Your rights and controls” for
              exactly what we send and how to opt out.
            </li>
          </ul>
        </Section>

        <Section title="How long we keep it">
          <ul>
            <li>
              <strong>Account & dietary profile:</strong> kept for as long as your account is open;
              removed when you delete it (see below).
            </li>
            <li>
              <strong>Reviews & suggested edits:</strong> kept as part of the shared menu graph; if
              you delete your account we delete or anonymize them.
            </li>
            <li>
              <strong>Restaurant-visit history:</strong> kept for as long as your account is open.
              After you delete your account it’s removed from active systems within 30 days and
              fully purged within 12 months.
            </li>
          </ul>
        </Section>

        <Section title="Your rights and controls">
          <ul>
            <li>
              <strong>Access / export your data:</strong> email{' '}
              <a href="mailto:privacy@bite-worthy.com">privacy@bite-worthy.com</a> and we’ll send a
              JSON archive within 30 days.
            </li>
            <li>
              <strong>Delete your account:</strong> same email, same window. We remove your personal
              data within 30 days and delete or anonymize your reviews. Some records may be retained
              where the law requires it.
            </li>
            <li>
              <strong>Correct your data:</strong> update your dietary profile any time in the app;
              for anything else, email us and we’ll fix it.
            </li>
            <li>
              <strong>Opt out of analytics:</strong> on web, analytics are on by default — turn them
              off with the toggle in <em>/profile/settings</em>, and we honor your browser’s
              Do-Not-Track signal automatically. On mobile, analytics are off by default and only
              fire if you enable them in <em>Settings → Analytics</em>. When analytics are on and
              you’re signed in, the funnel events (e.g. <em>app_open</em>, <em>menu_filtered</em>)
              are linked to your account and include coarse signals such as your strictness setting,
              which dietary preset you use, and counts of hidden/visible items. We never send review
              text, your email, or your specific avoid-lists.
            </li>
            <li>
              <strong>We do not sell or share</strong> your personal information, and we will not
              discriminate against you for exercising any of these rights.
            </li>
          </ul>
          <p>
            BiteWorthy is available in the United States at launch. If you’re in the EU or UK,
            additional rights may apply — contact us and we’ll honor them.
          </p>
        </Section>

        <Section title="Children">
          <p>
            BiteWorthy is for diners managing their own or their family’s dietary needs. You must be
            at least 13 to create an account. If we learn we’ve collected personal data from a child
            under 13, we delete it. BiteWorthy is not directed at children under 13.
          </p>
        </Section>

        <Section title="Changes">
          <p>
            We’ll update the date at the top when this page changes. Material changes get a
            highlighted note on the homepage and an email to active accounts.
          </p>
        </Section>

        <Section title="Contact">
          <p>
            Email <a href="mailto:privacy@bite-worthy.com">privacy@bite-worthy.com</a> for anything
            in this policy, including data access, deletion, or correction requests. For copyright
            takedowns, see <a href="/terms#copyright">Terms § Copyright & DMCA</a>.
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
      <strong>Draft.</strong> This template fills the App Privacy disclosures with BiteWorthy’s
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
