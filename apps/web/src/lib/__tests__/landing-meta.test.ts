import { describe, expect, it } from 'vitest';
import { buildLandingMetadata } from '../landing-meta';

describe('buildLandingMetadata', () => {
  it('builds the canonical title + description (deterministic strings)', () => {
    const meta = buildLandingMetadata({ siteUrl: 'https://bite-worthy.com' });
    expect(meta.title).toBe('BiteWorthy — Scan any menu, see only what you can eat');
    expect(meta.description).toMatch(/celiac, allergies, vegan/);
  });

  it('strips trailing slashes from siteUrl when composing OG URL + image', () => {
    const meta = buildLandingMetadata({ siteUrl: 'https://bite-worthy.com////' });
    expect(meta.openGraph?.url).toBe('https://bite-worthy.com');
    const images = meta.openGraph?.images;
    const first = Array.isArray(images) ? images[0] : images;
    const url = (first as { url?: string } | undefined)?.url;
    expect(url).toBe('https://bite-worthy.com/og.png');
  });

  it('emits Twitter summary_large_image with the same OG image', () => {
    const meta = buildLandingMetadata({ siteUrl: 'https://bite-worthy.com' });
    const twitter = meta.twitter as { card?: string; images?: unknown } | undefined;
    expect(twitter?.card).toBe('summary_large_image');
    const twitterImages = twitter?.images;
    const first = Array.isArray(twitterImages) ? twitterImages[0] : twitterImages;
    expect(first).toBe('https://bite-worthy.com/og.png');
  });

  it('sets canonical to / so preview deploys do not split SEO', () => {
    const meta = buildLandingMetadata({ siteUrl: 'https://branch--biteworthy.vercel.app' });
    expect(meta.alternates?.canonical).toBe('/');
    expect(meta.metadataBase?.toString()).toBe('https://branch--biteworthy.vercel.app/');
  });

  it('includes BiteWorthy as the OG site name', () => {
    const meta = buildLandingMetadata({ siteUrl: 'https://bite-worthy.com' });
    expect((meta.openGraph as { siteName?: string } | undefined)?.siteName).toBe('BiteWorthy');
  });
});
