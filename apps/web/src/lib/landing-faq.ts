/**
 * Landing-page FAQ copy. One array drives the visible section and the
 * FAQPage JSON-LD so the two cannot drift.
 *
 * Answers are one sentence each, taken from repo-verified sources — not
 * invented accuracy rates, and not "safe"/medical claims. Citations live
 * on the PR, not in this file.
 */

export interface LandingFaqItem {
  question: string;
  answer: string;
}

export const LANDING_FAQS: readonly LandingFaqItem[] = [
  {
    question: 'How accurate is BiteWorthy?',
    answer:
      'BiteWorthy is a planning aid, not a guarantee — dietary info can be wrong or out of date, so always confirm with the restaurant.',
  },
  {
    question: 'What can I scan?',
    answer: 'Menus arrive by photo, PDF, or link.',
  },
  {
    question: 'How does BiteWorthy handle my privacy?',
    answer:
      'BiteWorthy does not sell your personal information, and your dietary profile is never shown publicly.',
  },
  {
    question: 'How much does BiteWorthy cost?',
    answer: 'Free during the Durango beta.',
  },
  {
    question: 'Where can I use BiteWorthy?',
    answer: 'BiteWorthy is on the web at bite-worthy.com; iOS and Android apps are coming soon.',
  },
];

export function faqPageJsonLd(): Record<string, unknown> {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: LANDING_FAQS.map((faq) => ({
      '@type': 'Question',
      name: faq.question,
      acceptedAnswer: {
        '@type': 'Answer',
        text: faq.answer,
      },
    })),
  };
}

export function softwareApplicationJsonLd(siteUrl: string): Record<string, unknown> {
  const origin = siteUrl.replace(/\/+$/, '');
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'BiteWorthy',
    applicationCategory: 'LifestyleApplication',
    operatingSystem: 'Web',
    url: `${origin}/`,
    offers: {
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'USD',
      description: 'Free during the Durango beta',
    },
  };
}
