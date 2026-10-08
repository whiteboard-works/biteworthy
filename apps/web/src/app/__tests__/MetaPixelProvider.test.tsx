import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render, waitFor } from '@testing-library/react';

/**
 * The live Pixel (PR #827) rendered fbq init into SSR HTML, so
 * `/r/<slug>?p=<token>` reached Meta before any scrubber. Consent and
 * sanitization have to happen before the Script is allowed to mount.
 */

const scripts: string[] = [];
let pathname = '/';

vi.mock('next/navigation', () => ({
  usePathname: () => pathname,
}));

vi.mock('next/script', () => ({
  default: function Script({
    dangerouslySetInnerHTML,
  }: {
    dangerouslySetInnerHTML?: { __html: string };
  }) {
    if (dangerouslySetInnerHTML?.__html) scripts.push(dangerouslySetInnerHTML.__html);
    return null;
  },
}));

const { MetaPixelProvider, trackMetaEvent } = await import('../_MetaPixelProvider');

describe('MetaPixelProvider consent + sanitizer bootstrap', () => {
  beforeEach(() => {
    scripts.length = 0;
    pathname = '/';
    localStorage.clear();
    Object.defineProperty(navigator, 'doNotTrack', { value: null, configurable: true });
  });

  afterEach(() => {
    Object.defineProperty(navigator, 'doNotTrack', { value: null, configurable: true });
  });

  it('mounts a bootstrap that sanitizes, disables autoConfig, then inits', async () => {
    render(<MetaPixelProvider />);
    await waitFor(() => expect(scripts.length).toBeGreaterThan(0));
    const html = scripts[0] ?? '';
    expect(html).toContain('"p"');
    expect(html).toContain('"license_key"');
    expect(html).toContain('"email"');
    expect(html).toContain("fbq('set', 'autoConfig', false");
    expect(html).toContain("fbq('init', '1775852390205529')");
    expect(html.indexOf('history.replaceState')).toBeLessThan(html.indexOf("fbq('init'"));
  });

  it('never mounts the Pixel when the browser sends Do-Not-Track', async () => {
    Object.defineProperty(navigator, 'doNotTrack', { value: '1', configurable: true });
    render(<MetaPixelProvider />);
    await new Promise((r) => setTimeout(r, 20));
    expect(scripts).toHaveLength(0);
  });

  it('never mounts the Pixel after the visitor opted out in settings', async () => {
    localStorage.setItem('bw_analytics_opt_out', '1');
    render(<MetaPixelProvider />);
    await new Promise((r) => setTimeout(r, 20));
    expect(scripts).toHaveLength(0);
  });

  it('never mounts the Pixel on admin routes', async () => {
    pathname = '/admin/restaurants';
    render(<MetaPixelProvider />);
    await new Promise((r) => setTimeout(r, 20));
    expect(scripts).toHaveLength(0);
  });
});

describe('trackMetaEvent', () => {
  const fbq = vi.fn();

  beforeEach(() => {
    fbq.mockReset();
    localStorage.clear();
    window.fbq = fbq;
    Object.defineProperty(navigator, 'doNotTrack', { value: null, configurable: true });
  });

  afterEach(() => {
    delete window.fbq;
  });

  it('does not fire when the visitor opted out', () => {
    localStorage.setItem('bw_analytics_opt_out', '1');
    trackMetaEvent('CompleteRegistration');
    expect(fbq).not.toHaveBeenCalled();
  });

  it('sanitizes URL params and drops sensitive keys before fbq sees them', () => {
    trackMetaEvent('ViewContent', {
      email: 'user@example.com',
      page_url: 'https://bite-worthy.com/r/cafe?p=secret',
      content_ids: ['1'],
    });
    expect(fbq).toHaveBeenCalledTimes(1);
    const args = fbq.mock.calls[0] ?? [];
    expect(args[0]).toBe('track');
    expect(args[1]).toBe('ViewContent');
    const params = args[2] as Record<string, unknown>;
    expect(params['email']).toBeUndefined();
    expect(params['page_url']).toBe('https://bite-worthy.com/r/cafe');
    expect(params['content_name']).toBe('BiteWorthy');
    expect(params['content_ids']).toEqual(['1']);
  });
});
