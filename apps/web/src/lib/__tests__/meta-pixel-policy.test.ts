import { afterEach, describe, expect, it } from 'vitest';
import { globalPrivacyControl, metaPixelPathAllowed } from '../meta-pixel-policy';

// Meta receives the full page address with every pixel event. The
// privacy policy promises it never learns a diet, a person, or anything
// after the "?"; these pin that promise to the code.
describe('metaPixelPathAllowed', () => {
  it('allows public marketing and browsing pages', () => {
    for (const path of ['/', '/signup', '/story', '/durango', '/restaurants']) {
      expect(metaPixelPathAllowed(path, '')).toBe(true);
    }
    expect(metaPixelPathAllowed('/restaurants/usa/colorado/durango/himalayan-kitchen', '')).toBe(
      true,
    );
  });

  it('refuses any address with a query string, which can carry the diet', () => {
    expect(
      metaPixelPathAllowed(
        '/restaurants/usa/colorado/durango/himalayan-kitchen',
        '?profile=celiac',
      ),
    ).toBe(false);
    expect(metaPixelPathAllowed('/signup', '?next=%2Fdurango%2Fceliac')).toBe(false);
    expect(metaPixelPathAllowed('/', '?p=share-token')).toBe(false);
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
      '/admin/users',
    ]) {
      expect(metaPixelPathAllowed(path, '')).toBe(false);
    }
  });

  it('excludes a page nobody has allowed yet', () => {
    expect(metaPixelPathAllowed('/some-new-page', '')).toBe(false);
    expect(metaPixelPathAllowed('/restaurantsx', '')).toBe(false);
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
