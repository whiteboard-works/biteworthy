import { describe, expect, it } from 'vitest';
import { LANDING_FAQS, faqPageJsonLd, softwareApplicationJsonLd } from '../landing-faq';

describe('LANDING_FAQS', () => {
  it('is five questions, each with one-sentence answers from verified copy', () => {
    expect(LANDING_FAQS).toHaveLength(5);
    for (const faq of LANDING_FAQS) {
      expect(faq.question.length).toBeGreaterThan(0);
      expect(faq.answer.length).toBeGreaterThan(0);
      expect(faq.answer).not.toMatch(/\d+\s*%/);
      expect(faq.answer).not.toMatch(/\bsafe\b/i);
    }
  });
});

describe('faqPageJsonLd', () => {
  it('repeats the visible FAQ questions and answers verbatim', () => {
    const json = faqPageJsonLd();
    expect(json['@type']).toBe('FAQPage');
    const entities = json.mainEntity as Array<{
      name: string;
      acceptedAnswer: { text: string };
    }>;
    expect(entities).toHaveLength(5);
    expect(entities.map((e) => e.name)).toEqual(LANDING_FAQS.map((f) => f.question));
    expect(entities.map((e) => e.acceptedAnswer.text)).toEqual(LANDING_FAQS.map((f) => f.answer));
  });
});

describe('softwareApplicationJsonLd', () => {
  it('describes BiteWorthy as a free Web app during the Durango beta', () => {
    const json = softwareApplicationJsonLd('https://bite-worthy.com');
    expect(json['@type']).toBe('SoftwareApplication');
    expect(json.name).toBe('BiteWorthy');
    expect(json.applicationCategory).toBe('LifestyleApplication');
    expect(json.operatingSystem).toBe('Web');
    expect(json.url).toBe('https://bite-worthy.com/');
    expect(json.offers).toEqual({
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'USD',
      description: 'Free during the Durango beta',
    });
  });

  it('strips a trailing slash on the origin so url is origin + `/`', () => {
    expect(softwareApplicationJsonLd('https://bite-worthy.com/').url).toBe(
      'https://bite-worthy.com/',
    );
  });
});
