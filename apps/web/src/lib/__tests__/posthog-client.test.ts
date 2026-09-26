import { describe, expect, it, vi } from 'vitest';
import {
  createPostHogClient,
  EXTENSION_NAME,
  initPostHog,
  scrubEvent,
  scrubUrl,
} from '../posthog-client';

/**
 * Phase 5.8-wiring — posthog-js adapter contract.
 *
 * The adapter is a thin passthrough; these tests pin the two
 * behaviors that affect the WBW Cross-Product project filtering:
 *
 *   1. `initPostHog` registers `extension: 'biteworthy'` so every
 *      event carries the WBW filter property.
 *   2. `createPostHogClient` forwards capture/identify/reset to the
 *      underlying SDK with no shape change.
 */

describe('initPostHog', () => {
  it('initializes the SDK with the apiKey + registers the extension super-property', () => {
    const client = {
      init: vi.fn(),
      register: vi.fn(),
    } as unknown as Parameters<typeof initPostHog>[0];

    initPostHog(client, 'phc_test_token');

    expect(client.init).toHaveBeenCalledTimes(1);
    expect(client.init).toHaveBeenCalledWith(
      'phc_test_token',
      expect.objectContaining({
        api_host: 'https://us.i.posthog.com',
        capture_pageview: 'history_change',
      }),
    );
    expect(client.register).toHaveBeenCalledWith({ extension: EXTENSION_NAME });
    expect(EXTENSION_NAME).toBe('biteworthy');
  });

  it('uses a custom apiHost when provided', () => {
    const client = {
      init: vi.fn(),
      register: vi.fn(),
    } as unknown as Parameters<typeof initPostHog>[0];

    initPostHog(client, 'phc_x', { apiHost: 'https://eu.i.posthog.com' });

    expect(client.init).toHaveBeenCalledWith(
      'phc_x',
      expect.objectContaining({ api_host: 'https://eu.i.posthog.com' }),
    );
  });
});

describe('createPostHogClient', () => {
  it('forwards capture / identify / reset to the SDK', () => {
    const client = {
      capture: vi.fn(),
      identify: vi.fn(),
      reset: vi.fn(),
    } as unknown as Parameters<typeof createPostHogClient>[0];
    const adapter = createPostHogClient(client);

    adapter.capture('app_open', { surface: 'web' });
    adapter.identify?.('user-1', { plan: 'free' });
    adapter.reset?.();

    expect(client.capture).toHaveBeenCalledWith('app_open', { surface: 'web' });
    expect(client.identify).toHaveBeenCalledWith('user-1', { plan: 'free' });
    expect(client.reset).toHaveBeenCalled();
  });
});

// /privacy promises analytics never carry what someone avoids or types.
// Autocapture sent clicked element text (a celiac preset, chat messages)
// and the project turns session replay on for its other sites, so both
// must be refused by this client, not left to project defaults.
describe('initPostHog privacy settings', () => {
  it('captures no clicked text, no replays, and scrubs every event', () => {
    const client = { init: vi.fn(), register: vi.fn() } as unknown as Parameters<
      typeof initPostHog
    >[0];

    initPostHog(client, 'phc_test_token');

    expect(client.init).toHaveBeenCalledWith(
      'phc_test_token',
      expect.objectContaining({
        autocapture: false,
        disable_session_recording: true,
        before_send: scrubEvent,
      }),
    );
  });
});

describe('scrubUrl', () => {
  it('drops the query string, which can carry a share token or a diet', () => {
    expect(scrubUrl(`${window.location.origin}/restaurants/ninis?p=abc&profile=celiac`)).toBe(
      `${window.location.origin}/restaurants/ninis`,
    );
  });

  it('hides which diet page someone opened', () => {
    expect(scrubUrl('/durango/celiac')).toBe('/durango/:diet');
    expect(scrubUrl(`${window.location.origin}/durango/vegan#top`)).toBe(
      `${window.location.origin}/durango/:diet`,
    );
  });

  it('hides whose public profile was viewed', () => {
    expect(scrubUrl('/u/some_diner')).toBe('/u/:handle');
  });

  it('keeps only the origin of an outside referrer', () => {
    expect(scrubUrl('https://www.google.com/search?q=celiac+tacos')).toBe('https://www.google.com');
  });
});

describe('scrubEvent', () => {
  it('scrubs page-view URLs and the person-property copies', () => {
    const origin = window.location.origin;
    const event = {
      event: '$pageview',
      uuid: 'u',
      properties: {
        $current_url: `${origin}/durango/celiac?profile=celiac`,
        $pathname: '/durango/celiac',
        $referrer: '$direct',
      },
      $set_once: { $initial_current_url: `${origin}/r/ninis?p=token` },
    } as unknown as Parameters<typeof scrubEvent>[0];

    const out = scrubEvent(event)!;

    expect(out.properties).toMatchObject({
      $current_url: `${origin}/durango/:diet`,
      $pathname: '/durango/:diet',
      $referrer: '$direct',
    });
    expect(out.$set_once).toMatchObject({ $initial_current_url: `${origin}/r/ninis` });
  });
});

describe('scrubUrl fallback', () => {
  it('still hides the diet when a relative value will not parse as a URL', () => {
    expect(scrubUrl('/durango/celiac?x=[')).toBe('/durango/:diet');
  });
});
