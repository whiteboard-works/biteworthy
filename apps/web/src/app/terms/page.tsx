import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * Phase 5.9 — terms of service template.
 *
 * **DRAFT — needs lawyer review before App Store submission.**
 *
 * Legal-remediation Phase 1 (see docs/plans/legal-remediation.md)
 * added the standard protective clauses a real ToS needs: warranty
 * disclaimer (AS IS), limitation of liability, indemnification,
 * arbitration + class-action waiver (with 30-day opt-out), a Copyright
 * & DMCA section, and an acceptance clause. These are solid drafts;
 * a licensed Colorado attorney finalizes them before the DRAFT banner
 * comes off (legal-remediation L1).
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

const LAST_UPDATED = '2026-06-14';

export default function TermsPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Legal</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">
        Terms of Service
      </h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">Last updated: {LAST_UPDATED}</p>

      <DraftBanner />

      <SummaryDisclaimer />

      <article className="prose prose-zinc mt-bw-8 max-w-none text-zinc-800">
        <Section title="Acceptance of these terms">
          <p>
            By creating an account or using BiteWorthy, you agree to these Terms and to our{' '}
            <a href="/privacy">Privacy Policy</a>. If you don’t agree, please don’t use the service.
            You must be at least 13 years old to use BiteWorthy.
          </p>
        </Section>

        <Section title="The bargain">
          <p>
            BiteWorthy is a free dietary filter for restaurant menus. By using it you agree to use
            it in good faith and to understand what it can and can’t promise (see “The allergen
            disclaimer” below). If those don’t work for you, please don’t use the service.
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
              <strong>We can be wrong in the dangerous direction.</strong> We may fail to flag an
              allergen the menu text didn’t spell out, so a dish that isn’t safe for you can still
              appear in your filtered results. Treat every result as a starting point, not a
              guarantee.
            </li>
            <li>
              Always confirm with the restaurant before ordering anything that triggers a serious
              allergy.
            </li>
            <li>
              The “hidden — contains dairy (cheese)” chip is our best guess. The “visible” chip is
              also our best guess.
            </li>
            <li>
              We do not recommend BiteWorthy as the sole tool for managing anaphylactic allergies.
              Carry your prescribed treatment.
            </li>
          </ul>
        </Section>

        <Section title="Disclaimer of warranties">
          {/*
            Conspicuous per UCC §2-316 — a warranty disclaimer must stand
            out to be enforceable, so the operative language is boxed and
            partly capitalized rather than buried in prose.
          */}
          <Conspicuous>
            <p>
              BITEWORTHY IS PROVIDED <strong>“AS IS”</strong> AND{' '}
              <strong>“AS AVAILABLE,”</strong> WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR
              IMPLIED — INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
              PARTICULAR PURPOSE, ACCURACY, AND NON-INFRINGEMENT.
            </p>
            <p className="mt-bw-2">
              We do not warrant that the dietary information is accurate, complete, or current, or
              that the service will be uninterrupted or error-free. Some jurisdictions don’t allow
              the exclusion of certain warranties, so parts of this may not apply to you.
            </p>
          </Conspicuous>
        </Section>

        <Section title="Limitation of liability">
          <Conspicuous>
            <p>
              TO THE MAXIMUM EXTENT PERMITTED BY LAW, BITEWORTHY AND ITS OPERATORS WILL NOT BE
              LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR
              FOR ANY LOSS ARISING FROM YOUR RELIANCE ON THE DIETARY INFORMATION — INCLUDING ANY
              ALLERGIC REACTION, ILLNESS, OR INJURY. OUR TOTAL LIABILITY FOR ANY CLAIM RELATING TO
              THE SERVICE IS LIMITED TO USD 100.
            </p>
            <p className="mt-bw-2">
              Some jurisdictions don’t allow these limitations, and{' '}
              <strong>nothing in these Terms limits any liability that can’t be limited by law</strong>
              .
            </p>
          </Conspicuous>
        </Section>

        <Section title="Indemnification">
          <p>
            You agree to indemnify and hold harmless BiteWorthy and its operators from any claim or
            demand arising out of content you submit (reviews, photos, suggested edits), any URL or
            menu you submit to the ingestion pipeline, your violation of these Terms, or your
            violation of any law or third-party right.
          </p>
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
              dish or restaurant. Don’t upload anything you don’t have rights to.
            </li>
          </ul>
        </Section>

        <Section title="Copyright & DMCA" id="copyright">
          <p>
            BiteWorthy respects intellectual property. If you believe content on BiteWorthy
            infringes your copyright — including a menu image or a dish photo — send a notice to{' '}
            <a href="mailto:legal@bite-worthy.com">legal@bite-worthy.com</a> that includes: (1)
            identification of the work; (2) the URL or location of the material on BiteWorthy; (3)
            your contact information; (4) a statement that you have a good-faith belief the use
            isn’t authorized; (5) a statement, under penalty of perjury, that the notice is accurate
            and that you’re the owner or authorized to act for them; and (6) your signature.
          </p>
          <p>
            We remove material that infringes and terminate repeat infringers. If you believe your
            content was removed in error, you may send a counter-notice to the same address.
          </p>
        </Section>

        <Section title="Restaurant claims">
          <p>
            Phase 4.9’s claim flow lets a restaurant owner verify ownership via a domain-email
            check. Once verified, the owner can edit menu items and respond to reviews. Verifying
            doesn’t grant the owner the right to delete unfavorable reviews — moderation still goes
            through the queue.
          </p>
        </Section>

        <Section title="Acceptable use">
          <ul>
            <li>No spam, abuse, harassment, or bot-driven submissions.</li>
            <li>Don’t scrape the API at a rate that affects other users.</li>
            <li>
              Don’t pretend to be a restaurant owner you’re not. The claim flow exists for a reason.
            </li>
            <li>
              Don’t upload menu images you don’t have permission to share. Most public menus are
              fine; some restaurants explicitly forbid republication.
            </li>
            <li>
              When you submit a menu URL or upload for ingestion, you confirm you have the right to
              share that content with us and that doing so doesn’t violate the source site’s terms
              or anyone’s copyright.
            </li>
          </ul>
        </Section>

        <Section title="Analytics" id="analytics">
          <p>
            On web, BiteWorthy uses PostHog for funnel analytics (events like <em>app_open</em>,{' '}
            <em>menu_filtered</em>). When you’re signed in these events are linked to your account
            and include coarse signals like your strictness setting, which dietary preset you use,
            and counts of hidden/visible items — never review text, your email, or your specific
            avoid-lists. We honor browser <em>Do-Not-Track</em> automatically and a per-user opt-out
            at <em>/profile/settings</em>.
          </p>
          <p>
            On mobile, analytics are <strong>off by default</strong>. They only fire if you
            explicitly enable them in <em>Settings → Analytics</em>. The App Store privacy
            questionnaire reflects this.
          </p>
        </Section>

        <Section title="Dispute resolution" id="disputes">
          <p>
            Please contact us first — most issues can be resolved by email. For any dispute that
            can’t be resolved informally, you and BiteWorthy agree to resolve it through{' '}
            <strong>binding individual arbitration</strong>, not in court, and you each waive the
            right to a jury trial and to participate in a <strong>class action</strong>.
          </p>
          <p>
            You may opt out of this arbitration agreement by emailing{' '}
            <a href="mailto:legal@bite-worthy.com">legal@bite-worthy.com</a> within 30 days of first
            accepting these Terms; opting out won’t affect the rest of the Terms. This section
            doesn’t apply to small-claims matters or to requests for injunctive relief.
          </p>
        </Section>

        <Section title="Governing law">
          <p>
            These terms are governed by the laws of the State of Colorado, USA. Subject to the
            arbitration agreement above, disputes go to the state or federal courts located in La
            Plata County, Colorado.
          </p>
        </Section>

        <Section title="Termination">
          <p>
            You can delete your account at any time (see <a href="/privacy">Privacy Policy</a>). We
            can suspend accounts that violate these terms; we’ll explain why if it happens.
          </p>
        </Section>

        <Section title="Contact">
          <p>
            <a href="mailto:hello@bite-worthy.com">hello@bite-worthy.com</a> for anything in these
            terms. Legal notices to <a href="mailto:legal@bite-worthy.com">legal@bite-worthy.com</a>
            .
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

/**
 * A prominent, plain-language "read this first" disclaimer at the top of
 * the Terms. Conspicuous on purpose — the protective clauses below only
 * help if a user can't miss the gist.
 */
function SummaryDisclaimer(): ReactElement {
  return (
    <div
      role="note"
      data-testid="summary-disclaimer"
      className="mt-bw-4 rounded-bw-md border-2 border-bite/50 bg-bite-light p-bw-4 text-bw-base text-bite-dark"
    >
      <p className="font-bold uppercase tracking-wide">Please read — use at your own risk</p>
      <p className="mt-bw-2">
        BiteWorthy is a planning aid, not a guarantee of safety. The dietary information can be
        wrong, incomplete, out of date, or mislabeled, and a dish that isn’t safe for you can still
        appear in your results. <strong>Always confirm with the restaurant before you order</strong>
        , especially for a serious allergy. Your use of BiteWorthy is at your own risk; see the
        allergen disclaimer and limitation of liability below.
      </p>
    </div>
  );
}

/**
 * Conspicuous callout for the warranty + liability disclaimers — boxed
 * and set off so they're "conspicuous" (UCC §2-316) rather than buried.
 */
function Conspicuous({ children }: { children: ReactElement | ReactElement[] }): ReactElement {
  return (
    <div className="rounded-bw-md border border-zinc-300 bg-zinc-50 p-bw-4 text-bw-sm font-semibold text-zinc-900">
      {children}
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
