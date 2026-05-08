import { createPostHogClient, EXTENSION_NAME, registerExtension } from '../../lib/posthog-client';
import type PostHog from 'posthog-react-native';

/**
 * Phase 5.8-wiring — posthog-react-native adapter contract.
 *
 * Parallel to the web side; mobile differs in two ways:
 *   - `register` is async (returns Promise<void>); fire-and-forget
 *     is fine because subsequent capture calls retry from the
 *     persisted store on reconnect.
 *   - The instance is constructed by the caller (not a singleton),
 *     so `init` lives at the layout boundary, not in the adapter.
 */

function fakeClient() {
  return {
    register: jest.fn().mockResolvedValue(undefined),
    capture: jest.fn(),
    identify: jest.fn(),
    reset: jest.fn().mockResolvedValue(undefined),
  } as unknown as jest.Mocked<PostHog>;
}

describe('registerExtension', () => {
  it('registers the WBW extension super-property as biteworthy', () => {
    const client = fakeClient();
    registerExtension(client);
    expect(client.register).toHaveBeenCalledWith({ extension: EXTENSION_NAME });
    expect(EXTENSION_NAME).toBe('biteworthy');
  });
});

describe('createPostHogClient', () => {
  it('forwards capture / identify / reset to the SDK', () => {
    const client = fakeClient();
    const adapter = createPostHogClient(client);

    adapter.capture('app_open', { surface: 'ios' });
    adapter.identify?.('user-1', { plan: 'free' });
    adapter.reset?.();

    expect(client.capture).toHaveBeenCalledWith('app_open', { surface: 'ios' });
    expect(client.identify).toHaveBeenCalledWith('user-1', { plan: 'free' });
    expect(client.reset).toHaveBeenCalled();
  });
});
