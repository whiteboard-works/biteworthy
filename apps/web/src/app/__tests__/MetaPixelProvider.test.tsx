import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from '@testing-library/react';
import { OPT_OUT_KEY } from '../../lib/track';

let mockPath = '/';
vi.mock('next/navigation', () => ({ usePathname: () => mockPath }));

import { MetaPixelProvider, markMetaRegistration } from '../_MetaPixelProvider';

/**
 * Every request the site sends Meta is an image request built by
 * lib/meta-pixel.ts. These capture each one and check what it carries,
 * which is everything Meta can learn from the website.
 */
const sent: { src: string; referrerPolicy: string }[] = [];
class FakeImage {
  referrerPolicy = '';
  set src(value: string) {
    sent.push({ src: value, referrerPolicy: this.referrerPolicy });
  }
}

function visit(path: string, referrer = '') {
  window.history.pushState({}, '', path);
  mockPath = new URL(path, window.location.origin).pathname;
  Object.defineProperty(document, 'referrer', { value: referrer, configurable: true });
}

const params = (i = 0) => new URL(sent[i]!.src).searchParams;
const nav = navigator as { globalPrivacyControl?: boolean };

beforeEach(() => {
  sent.length = 0;
  vi.stubGlobal('Image', FakeImage);
  localStorage.clear();
  delete nav.globalPrivacyControl;
  document.cookie = '_fbc=; max-age=0; path=/';
  document.cookie = '_fbp=; max-age=0; path=/';
});
afterEach(() => {
  vi.unstubAllGlobals();
  visit('/');
});

describe('Meta Pixel requests', () => {
  it('sends the path only, never the diet in the query', () => {
    visit('/restaurants/usa/colorado/durango/himalayan-kitchen?profile=celiac#top');
    render(<MetaPixelProvider />);

    expect(sent).toHaveLength(1);
    expect(params().get('ev')).toBe('PageView');
    expect(params().get('dl')).toBe(
      `${window.location.origin}/restaurants/usa/colorado/durango/himalayan-kitchen`,
    );
    expect(sent[0]!.src).not.toContain('celiac');
    // The browser must not attach the full address as a Referer header.
    expect(sent[0]!.referrerPolicy).toBe('no-referrer');
  });

  it('sends nothing from a diet page or a profile', () => {
    visit('/durango/celiac');
    render(<MetaPixelProvider />);
    visit('/u/diner_jane');
    render(<MetaPixelProvider />);
    expect(sent).toHaveLength(0);
  });

  it('cleans the referrer of a diet link', () => {
    visit('/story', `${window.location.origin}/durango/celiac?profile=celiac`);
    render(<MetaPixelProvider />);
    expect(params().get('rl')).toBe(window.location.origin);
  });

  it('sends nothing when the visitor opted out or sent Global Privacy Control', () => {
    visit('/story');
    localStorage.setItem(OPT_OUT_KEY, '1');
    const { unmount } = render(<MetaPixelProvider />);
    unmount();
    localStorage.clear();
    nav.globalPrivacyControl = true;
    render(<MetaPixelProvider />);
    expect(sent).toHaveLength(0);
  });

  it('keeps an ad click id as a cookie and credits it, without sending the query', () => {
    visit('/?fbclid=AbC123&utm_source=fb');
    render(<MetaPixelProvider />);
    expect(params().get('fbc')).toMatch(/^fb\.1\.\d+\.AbC123$/);
    expect(params().get('dl')).toBe(`${window.location.origin}/`);
    expect(sent[0]!.src).not.toContain('utm_source');
  });

  it('sends a sign-up as CompleteRegistration from the sign-up page', () => {
    visit('/signup?next=%2Fdurango%2Fceliac');
    markMetaRegistration();
    expect(params().get('ev')).toBe('CompleteRegistration');
    expect(params().get('dl')).toBe(`${window.location.origin}/signup`);
    expect(sent[0]!.src).not.toContain('celiac');
  });
});
