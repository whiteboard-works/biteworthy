import { describe, expect, it, vi } from 'vitest';
import { createPostHogClient, EXTENSION_NAME, initPostHog } from '../posthog-client';

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
        capture_pageview: false,
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
