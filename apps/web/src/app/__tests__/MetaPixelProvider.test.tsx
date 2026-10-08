import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { OPT_OUT_KEY } from '../../lib/track';

let mockPath = '/';
vi.mock('next/navigation', () => ({ usePathname: () => mockPath }));
// The real <Script> injects into <head>; a marker is enough to see whether
// Meta's code would load at all.
vi.mock('next/script', () => ({ default: () => <div data-testid="meta-script" /> }));

import { MetaPixelProvider, markMetaRegistration } from '../_MetaPixelProvider';

/**
 * The privacy policy promises Meta never learns a diet: no pixel on diet
 * pages or when any opt-out is set, nothing from a page reached from a
 * diet link, one PageView per page, and the sign-up conversion sent from
 * a later allowed page rather than from the page holding the email field.
 */
function visit(path: string, referrer = '') {
  window.history.pushState({}, '', path);
  mockPath = new URL(path, window.location.origin).pathname;
  Object.defineProperty(document, 'referrer', { value: referrer, configurable: true });
}

const nav = navigator as { globalPrivacyControl?: boolean };
const fbq = vi.fn();

beforeEach(() => {
  localStorage.clear();
  sessionStorage.clear();
  delete nav.globalPrivacyControl;
  fbq.mockReset();
  delete (window as { fbq?: unknown }).fbq;
  delete window.__bwMetaReady;
});
afterEach(() => visit('/'));

describe('MetaPixelProvider', () => {
  it('loads nothing on a page that carries a diet', () => {
    visit('/restaurants/usa/colorado/durango/himalayan-kitchen?profile=celiac');
    render(<MetaPixelProvider />);
    expect(screen.queryByTestId('meta-script')).toBeNull();
  });

  it('loads nothing when the visitor has opted out or sent Global Privacy Control', () => {
    visit('/story');
    localStorage.setItem(OPT_OUT_KEY, '1');
    const { unmount } = render(<MetaPixelProvider />);
    expect(screen.queryByTestId('meta-script')).toBeNull();
    unmount();

    localStorage.clear();
    nav.globalPrivacyControl = true;
    render(<MetaPixelProvider />);
    expect(screen.queryByTestId('meta-script')).toBeNull();
  });

  it('loads nothing on an allowed page reached from a diet link', () => {
    visit('/story', `${window.location.origin}/restaurants/usa/colorado/durango/x?profile=celiac`);
    render(<MetaPixelProvider />);
    expect(screen.queryByTestId('meta-script')).toBeNull();
  });

  it('sends exactly one PageView on an allowed page', () => {
    visit('/story');
    render(<MetaPixelProvider />);
    expect(screen.getByTestId('meta-script')).toBeTruthy();

    // What the loaded script does: define fbq, then call the ready hook.
    window.fbq = fbq as unknown as Window['fbq'];
    window.__bwMetaReady?.();
    expect(fbq.mock.calls.filter((c) => c[1] === 'PageView')).toHaveLength(1);
  });

  it('sends a recorded sign-up with the next allowed PageView, once', () => {
    visit('/signup');
    markMetaRegistration();

    visit('/');
    render(<MetaPixelProvider />);
    window.fbq = fbq as unknown as Window['fbq'];
    window.__bwMetaReady?.();
    expect(fbq).toHaveBeenCalledWith('track', 'CompleteRegistration', {
      content_name: 'BiteWorthy',
    });

    fbq.mockReset();
    window.__bwMetaReady?.();
    expect(fbq).not.toHaveBeenCalledWith('track', 'CompleteRegistration', expect.anything());
  });

  it('records no sign-up for a visitor who opted out', () => {
    localStorage.setItem(OPT_OUT_KEY, '1');
    markMetaRegistration();
    expect(sessionStorage.length).toBe(0);
  });
});
