import { describe, expect, it } from 'vitest';
import { buildLegalMetadata } from '../legal-meta';

describe('buildLegalMetadata', () => {
  it('composes the canonical title with the BiteWorthy suffix', () => {
    const meta = buildLegalMetadata({
      pageTitle: 'Privacy Policy',
      description: 'How we handle your data.',
      path: '/privacy',
      siteUrl: 'https://bite-worthy.com',
    });
    expect(meta.title).toBe('Privacy Policy — BiteWorthy');
    expect(meta.description).toBe('How we handle your data.');
  });

  it('sets canonical + OG url against the page path, not just the origin', () => {
    const meta = buildLegalMetadata({
      pageTitle: 'Terms of Service',
      description: '...',
      path: '/terms',
      siteUrl: 'https://bite-worthy.com',
    });
    expect(meta.alternates?.canonical).toBe('/terms');
    expect((meta.openGraph as { url?: string } | undefined)?.url).toBe(
      'https://bite-worthy.com/terms',
    );
  });

  it('strips trailing slashes from the siteUrl when composing OG url', () => {
    const meta = buildLegalMetadata({
      pageTitle: 'Privacy Policy',
      description: '...',
      path: '/privacy',
      siteUrl: 'https://bite-worthy.com////',
    });
    expect((meta.openGraph as { url?: string } | undefined)?.url).toBe(
      'https://bite-worthy.com/privacy',
    );
  });

  it('emits Twitter "summary" card (text-only — legal pages have no hero image)', () => {
    const meta = buildLegalMetadata({
      pageTitle: 'Privacy Policy',
      description: '...',
      path: '/privacy',
      siteUrl: 'https://bite-worthy.com',
    });
    expect((meta.twitter as { card?: string } | undefined)?.card).toBe('summary');
  });

  it('marks the page indexable + follow (legal pages should appear in search)', () => {
    const meta = buildLegalMetadata({
      pageTitle: 'Privacy Policy',
      description: '...',
      path: '/privacy',
      siteUrl: 'https://bite-worthy.com',
    });
    expect((meta.robots as { index?: boolean; follow?: boolean } | undefined)?.index).toBe(true);
    expect((meta.robots as { index?: boolean; follow?: boolean } | undefined)?.follow).toBe(true);
  });
});
