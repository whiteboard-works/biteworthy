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
 * 2026-10-05: the Anthropic entry used to say the profile is never
 * sent. The chat has sent it with every turn since M4, and now sends
 * the user's saved chat notes too, so the entry says so. It also said
 * reviews are never sent; the chat's review tools read and write them,
 * for any user's chat, not only the author's.
 *
 * 2026-10-06: diner dish-photo submissions — stored without EXIF/GPS,
 * unpublished until a moderator approves them, then optionally credited
 * on the dish page.
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

const LAST_UPDATED = '2026-10-06';

export default function PrivacyPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Legal</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">Privacy Policy</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">Last updated: {LAST_UPDATED}</p>


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
              taste signals (ingredients/tags you like or dislike) you add to improve your picks,
              and any notes you save for the chat assistant. Stored against your account so it
              follows you across devices.
            </li>
            <li>
              <strong>Reviews:</strong> the rating, body, and optional photo you submit on a dish.
              Reviews are public — see “What’s public” below. Photos are stored on Cloudflare R2
              (see “Where data lives”).
            </li>
            <li>
              <strong>Dish photos:</strong> if you submit a photo of a dish (from the dish page, or
              by offering a review photo), we store the image and whether you confirmed you took it.
              Location and other camera metadata (EXIF/GPS) is stripped before the file is saved. A
              moderator reviews every submission before it can appear as the dish photo.
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
            <li>Address or GPS coordinates (we strip location metadata from photos you upload).</li>
            <li>Device fingerprints, advertising IDs, or cross-app tracking signals.</li>
          </ul>
        </Section>

        <Section title="What's public">
          <p>
            Your reviews — the rating, text, and any photo — appear publicly next to your display
            handle on the dish page and on your profile at <em>/u/your-handle</em>. If a moderator
            approves a dish photo you submitted, it can appear as that dish&apos;s photo with a
            small &ldquo;Photo by &lt;your display name&gt;&rdquo; credit. Your{' '}
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
              <strong>Cloudflare R2</strong>: review photos, diner-submitted dish photos (metadata
              stripped; unpublished until a moderator approves them), and the cropped per-dish
              photos that the ingestion pipeline extracts from menu images.
            </li>
            <li>
              <strong>Anthropic</strong>: when a menu is being ingested, the menu image is sent to
              Anthropic Claude for OCR + structuring. The image leaves our servers but is not used
              to train the model. When you use the chat, your messages, your dietary profile, any
              notes you saved for the assistant, and your own reviews when you ask about them
              (including any hidden by moderation) are sent to Anthropic so it can answer. Reviews
              are public, so when anyone asks the chat about a dish, the reviews on it (with the
              reviewer&apos;s username and display name) can be sent to Anthropic too.
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
              <strong>Dish photo submissions:</strong> pending ones are deleted with your account.
              An approved photo that became the dish photo stays on the menu (the byline is already
              stored as a name, not a live link to your account).
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
              fire if you enable them in <em>Settings → Analytics</em>. Funnel events are tied to a
              random analytics ID, <strong>not to your account</strong> — signing in does not
              connect them to your identity. What they carry is
              deliberately narrow: <em>menu_filtered</em> sends the restaurant, how many items were
              visible or hidden, and which <em>kind</em> of filter was applied — not the filter
              itself. Toggling strictness on a menu sends the before and after value.
              Saving your dietary profile sends only that it happened, never the preset, the
              strictness, or how much you avoid — that association is the one we most want to
              avoid making. We never send review text, your email, or your specific avoid-lists.
              Page views send the page’s address with the part after the “?” removed, and without
              which diet page you opened or whose profile you viewed. Like every event, they also
              carry that random analytics ID and basic browser and device details (browser, OS,
              screen size, approximate location from your IP), and the domain of the site that
              sent you. We don’t record what you click or type, and we don’t record your session.
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
