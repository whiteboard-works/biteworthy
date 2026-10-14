import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from '@testing-library/react';
import { OPT_OUT_KEY } from '../../lib/track';
import { sendMetaEvent } from '../../lib/meta-pixel';

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
const nav = navigator as { globalPrivacyControl?: boolean; doNotTrack?: string };

beforeEach(() => {
  sent.length = 0;
  vi.stubGlobal('Image', FakeImage);
  localStorage.clear();
  delete nav.globalPrivacyControl;
  Object.defineProperty(navigator, 'doNotTrack', { value: null, configurable: true });
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
    // Live URL keeps the diet so a reload still applies it.
    expect(window.location.search).toContain('profile=celiac');
  });

  it('strips a share token from the pixel request, not the live URL', () => {
    visit('/restaurants/usa/colorado/durango/himalayan-kitchen?p=secret-token&view=menu');
    render(<MetaPixelProvider />);

    expect(sent).toHaveLength(1);
    expect(params().get('dl')).not.toContain('p=');
    expect(sent[0]!.src).not.toContain('secret-token');
    expect(window.location.search).toContain('p=secret-token');
    expect(window.location.search).toContain('view=menu');
  });

  it('leaves the shared filter on the live URL so reload and login next= keep it', () => {
    const path = '/restaurants/usa/colorado/durango/himalayan-kitchen';
    visit(`${path}?p=secret-token&profile=celiac`);
    const replaceStateSpy = vi.spyOn(history, 'replaceState');
    render(<MetaPixelProvider />);

    expect(replaceStateSpy).not.toHaveBeenCalled();
    replaceStateSpy.mockRestore();

    expect(window.location.search).toContain('p=secret-token');
    expect(window.location.search).toContain('profile=celiac');
    // ClaimSection rebuilds next= from location.search after a 401.
    const next = `${window.location.pathname}${window.location.search}`;
    expect(next).toBe(`${path}?p=secret-token&profile=celiac`);
    expect(sent[0]!.src).not.toContain('secret-token');
    expect(sent[0]!.src).not.toContain('celiac');
    expect(params().get('dl')).toBe(`${window.location.origin}${path}`);
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

  it('sends nothing when the browser sends Do-Not-Track', () => {
    visit('/story');
    Object.defineProperty(navigator, 'doNotTrack', { value: '1', configurable: true });
    render(<MetaPixelProvider />);
    expect(sent).toHaveLength(0);
  });

  it('never mounts a request on admin routes', () => {
    visit('/admin/restaurants');
    render(<MetaPixelProvider />);
    expect(sent).toHaveLength(0);
  });

  it('keeps an ad click id as a cookie and credits it, without sending the query', () => {
    visit('/?fbclid=AbC123&utm_source=fb');
    render(<MetaPixelProvider />);
    expect(params().get('fbc')).toMatch(/^fb\.1\.\d+\.AbC123$/);
    expect(params().get('dl')).toBe(`${window.location.origin}/`);
    expect(sent[0]!.src).not.toContain('utm_source');
    expect(sent[0]!.src).not.toContain('fbclid');
    // Live URL keeps the click id; only the outbound request is scrubbed.
    expect(window.location.search).toContain('fbclid=AbC123');
  });

  it('sends a sign-up as CompleteRegistration from the sign-up page', () => {
    visit('/signup?next=%2Fdurango%2Fceliac');
    markMetaRegistration();
    expect(params().get('ev')).toBe('CompleteRegistration');
    expect(params().get('dl')).toBe(`${window.location.origin}/signup`);
    expect(sent[0]!.src).not.toContain('celiac');
  });

  it('wraps extra event params so a share token or email never ships', () => {
    visit('/signup');
    sendMetaEvent('CompleteRegistration', {
      email: 'user@example.com',
      page_url: 'https://bite-worthy.com/r/cafe?p=secret#activate=z',
      content_ids: ['1'],
    });
    const src = sent[0]!.src;
    expect(src).not.toContain('user@example.com');
    expect(src).not.toContain('p=secret');
    expect(src).not.toContain('activate=z');
    expect(params().get('cd[page_url]')).toBe('https://bite-worthy.com/r/cafe');
    expect(params().get('cd[content_name]')).toBe('BiteWorthy');
    expect(params().get('cd[email]')).toBeNull();
  });
});
