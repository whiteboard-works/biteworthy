import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { LandingFaq } from '../_LandingFaq';
import { LANDING_FAQS, faqPageJsonLd } from '../../lib/landing-faq';
import { JsonLd } from '../../lib/json-ld';

function parsedJsonLd(container: HTMLElement): unknown[] {
  return [...container.querySelectorAll('script[type="application/ld+json"]')].map((el) =>
    JSON.parse(el.innerHTML),
  );
}

/**
 * WBW-204: a food-allergy tool has to answer "how accurate is this?"
 * in visible text, not only in the footer disclaimer. The FAQPage
 * JSON-LD must repeat that same wording — a schema block that drifts
 * from what the visitor reads is the failure this test exists to catch.
 */
describe('LandingFaq', () => {
  it('renders the five questions in visible text', () => {
    render(<LandingFaq />);
    expect(LANDING_FAQS).toHaveLength(5);
    for (const faq of LANDING_FAQS) {
      expect(screen.getByText(faq.question)).toBeInTheDocument();
      expect(screen.getByText(faq.answer)).toBeInTheDocument();
    }
  });

  it('emits FAQPage JSON-LD whose questions and answers equal the visible copy', () => {
    const { container } = render(
      <>
        <JsonLd data={faqPageJsonLd()} />
        <LandingFaq />
      </>,
    );

    const blocks = parsedJsonLd(container);
    const faqPage = blocks.find(
      (
        b,
      ): b is {
        '@type': string;
        mainEntity: Array<{ name: string; acceptedAnswer: { text: string } }>;
      } =>
        typeof b === 'object' && b !== null && (b as { '@type'?: string })['@type'] === 'FAQPage',
    );
    expect(faqPage).toBeDefined();
    expect(faqPage!.mainEntity).toHaveLength(5);

    const schemaQs = faqPage!.mainEntity.map((q) => q.name);
    const schemaAs = faqPage!.mainEntity.map((q) => q.acceptedAnswer.text);
    const visibleQs = LANDING_FAQS.map((f) => f.question);
    const visibleAs = LANDING_FAQS.map((f) => f.answer);

    expect(schemaQs).toEqual(visibleQs);
    expect(schemaAs).toEqual(visibleAs);

    for (const faq of LANDING_FAQS) {
      expect(screen.getByText(faq.question)).toBeInTheDocument();
      expect(screen.getByText(faq.answer)).toBeInTheDocument();
    }
  });
});
