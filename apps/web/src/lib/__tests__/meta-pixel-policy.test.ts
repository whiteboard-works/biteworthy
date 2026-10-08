import { afterEach, describe, expect, it } from 'vitest';
import {
  globalPrivacyControl,
  metaPixelReferrerAllowed,
  metaPixelUrlAllowed,
} from '../meta-pixel-policy';

// Meta receives the full page address and the previous page's address
// with every pixel event. The privacy policy promises it never learns a
// diet, a person, or anything after the "?"; these pin that to the code.
const at = (path: string) => metaPixelUrlAllowed(new URL(path, 'https://bite-worthy.com'));
const RESTAURANT = '/restaurants/usa/colorado/durango/himalayan-kitchen';

describe('metaPixelUrlAllowed', () => {
  it('allows public marketing and browsing pages', () => {
    for (const path of ['/', '/story', '/durango', '/restaurants', '/restaurants/usa']) {
      expect(at(path)).toBe(true);
    }
    expect(at(RESTAURANT)).toBe(true);
    expect(at(`${RESTAURANT}/items/abc-123`)).toBe(true);
  });

  it('refuses anything after "?" or "#", which can carry the diet', () => {
    expect(at(`${RESTAURANT}?profile=celiac`)).toBe(false);
    expect(at('/?p=share-token')).toBe(false);
    expect(at(`${RESTAURANT}#profile=celiac`)).toBe(false);
  });

  it('never fires on pages that reveal a diet, a person, or an account', () => {
    for (const path of [
      '/durango/celiac',
      '/u/diner_jane',
      '/history',
      '/chat',
      '/onboarding',
      '/profile/settings',
      '/admin',
      '/restaurants/new',
      `${RESTAURANT}/scan`,
      `${RESTAURANT}/suggestions`,
      `${RESTAURANT}/claim`,
    ]) {
      expect(at(path)).toBe(false);
    }
  });

  // Meta's automatic advanced matching can read email fields.
  it('stays off the sign-in and sign-up pages', () => {
    expect(at('/signup')).toBe(false);
    expect(at('/login')).toBe(false);
  });

  it('excludes a page nobody has allowed yet', () => {
    expect(at('/some-new-page')).toBe(false);
    expect(at('/restaurantsx')).toBe(false);
  });
});

describe('metaPixelReferrerAllowed', () => {
  const origin = 'https://bite-worthy.com';

  it('refuses a same-site referrer that carried a diet', () => {
    expect(metaPixelReferrerAllowed(`${origin}${RESTAURANT}?profile=celiac`, origin)).toBe(false);
    expect(metaPixelReferrerAllowed(`${origin}/durango/celiac`, origin)).toBe(false);
  });

  it('allows no referrer, an allowed same-site page, or another site', () => {
    expect(metaPixelReferrerAllowed('', origin)).toBe(true);
    expect(metaPixelReferrerAllowed(`${origin}/story`, origin)).toBe(true);
    expect(metaPixelReferrerAllowed('https://www.google.com/', origin)).toBe(true);
  });
});

describe('globalPrivacyControl', () => {
  const nav = navigator as { globalPrivacyControl?: boolean };
  afterEach(() => {
    delete nav.globalPrivacyControl;
  });

  it('reads the browser signal', () => {
    expect(globalPrivacyControl()).toBe(false);
    nav.globalPrivacyControl = true;
    expect(globalPrivacyControl()).toBe(true);
  });
});
