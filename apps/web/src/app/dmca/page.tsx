import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { buildLegalMetadata } from '../../lib/legal-meta';
import { DmcaForm } from './DmcaForm';

/**
 * Legal remediation E10 — the DMCA takedown page.
 *
 * Backs the ToS § Copyright clause: it lays out the §512(c)(3) notice
 * procedure and provides a structured form that files a notice into the
 * intake (POST /api/v1/dmca_notices). The designated-agent registration
 * itself is an external step (L2).
 */

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLegalMetadata({
  pageTitle: 'Copyright & DMCA',
  description:
    'How to report content on BiteWorthy that infringes your copyright, and how to file a counter-notice.',
  path: '/dmca',
  siteUrl: SITE_URL,
});

export default function DmcaPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Legal</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">Copyright & DMCA</h1>

      <article className="prose prose-zinc mt-bw-8 max-w-none text-zinc-800">
        <p>
          BiteWorthy respects intellectual property. If you believe content here — a menu image or
          a dish photo — infringes your copyright, send us a notice using the form below or by
          email to <a href="mailto:legal@bite-worthy.com">legal@bite-worthy.com</a>. We remove
          infringing material and terminate repeat infringers. See also the{' '}
          <a href="/terms#copyright">Terms § Copyright & DMCA</a>.
        </p>

        <h2 className="text-bw-xl font-bold text-zinc-900">What a notice needs</h2>
        <ul>
          <li>Identification of the copyrighted work.</li>
          <li>The URL or location of the material on BiteWorthy.</li>
          <li>Your contact information.</li>
          <li>A statement that you have a good-faith belief the use isn’t authorized.</li>
          <li>A statement, under penalty of perjury, that the notice is accurate and that you’re the owner or authorized to act for them.</li>
          <li>Your signature.</li>
        </ul>

        <h2 className="text-bw-xl font-bold text-zinc-900">Counter-notice</h2>
        <p>
          If you believe your content was removed in error, you may send a counter-notice to{' '}
          <a href="mailto:legal@bite-worthy.com">legal@bite-worthy.com</a>.
        </p>
      </article>

      <DmcaForm />
    </main>
  );
}
