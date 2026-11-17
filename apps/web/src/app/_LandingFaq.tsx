import type { ReactElement } from 'react';
import { LANDING_FAQS } from '../lib/landing-faq';

/**
 * Visible landing FAQ. Copy comes from LANDING_FAQS — the same array
 * that serializes the FAQPage JSON-LD — so a wording change cannot
 * update one surface and miss the other.
 */
export function LandingFaq(): ReactElement {
  return (
    <section data-testid="landing-faq" className="mx-auto max-w-3xl px-bw-6 py-bw-16">
      <h2 className="text-bw-2xl font-bold text-zinc-900">Frequently asked questions</h2>
      <dl className="mt-bw-8 space-y-bw-6">
        {LANDING_FAQS.map((faq) => (
          <div key={faq.question}>
            <dt className="text-bw-base font-bold text-zinc-900">{faq.question}</dt>
            <dd className="mt-bw-2 text-bw-base text-zinc-700">{faq.answer}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
