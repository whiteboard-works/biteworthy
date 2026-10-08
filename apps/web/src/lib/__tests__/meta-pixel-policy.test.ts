import { afterEach, describe, expect, it } from 'vitest';
import {
  globalPrivacyControl,
  metaPageAddress,
  metaPixelPathAllowed,
  metaReferrer,
} from '../meta-pixel-policy';

// The privacy policy promises Meta only ever sees allowed paths: never a
// diet, a person, or anything after "?" or "#". These pin that rule.
const ORIGIN = 'https://bite-worthy.com';
const RESTAURANT = '/restaurants/usa/colorado/durango/himalayan-kitchen';

describe('metaPixelPathAllowed', () => {
  it('allows public marketing, browsing, and sign-up pages', () => {
    for (const path of ['/', '/signup', '/story', '/durango', '/restaurants', '/restaurants/usa']) {
      expect(metaPixelPathAllowed(path)).toBe(true);
    }
    expect(metaPixelPathAllowed(RESTAURANT)).toBe(true);
    expect(metaPixelPathAllowed(`${RESTAURANT}/items/abc-123`)).toBe(true);
  });

  it('never allows pages that reveal a diet, a person, or an account', () => {
    for (const path of [
      '/durango/celiac',
      '/u/diner_jane',
      '/history',
      '/chat',
      '/onboarding',
      '/profile/settings',
      '/login',
      '/admin',
      '/restaurants/new',
      `${RESTAURANT}/scan`,
      `${RESTAURANT}/suggestions`,
      `${RESTAURANT}/claim`,
      '/some-new-page',
      '/restaurantsx',
    ]) {
      expect(metaPixelPathAllowed(path)).toBe(false);
    }
  });
});

describe('metaPageAddress', () => {
  it('is the origin and path only', () => {
    expect(metaPageAddress(ORIGIN, RESTAURANT)).toBe(`${ORIGIN}${RESTAURANT}`);
  });
});

describe('metaReferrer', () => {
  it('drops the query and hash from our own allowed pages', () => {
    expect(metaReferrer(`${ORIGIN}${RESTAURANT}?profile=celiac#x`, ORIGIN)).toBe(
      `${ORIGIN}${RESTAURANT}`,
    );
  });

  it('reduces our own non-allowed pages to the origin', () => {
    expect(metaReferrer(`${ORIGIN}/durango/celiac`, ORIGIN)).toBe(ORIGIN);
    expect(metaReferrer(`${ORIGIN}/u/diner_jane`, ORIGIN)).toBe(ORIGIN);
  });

  it('reduces another site to its origin', () => {
    expect(metaReferrer('https://www.google.com/search?q=celiac+durango', ORIGIN)).toBe(
      'https://www.google.com',
    );
  });

  it('sends nothing for no referrer or a malformed one', () => {
    expect(metaReferrer('', ORIGIN)).toBe('');
    expect(metaReferrer('not a url', ORIGIN)).toBe('');
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
