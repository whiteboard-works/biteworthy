import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from '@testing-library/react';

/**
 * posthog-js captures page views on its own once initialized, outside the
 * app's Tracker. So Do-Not-Track and the /profile/settings opt-out have to
 * stop initialization itself — gating only the Tracker would still send
 * every page view /privacy says an opted-out visitor never sends.
 */

const init = vi.fn();
vi.mock('posthog-js', () => ({
  default: { init: (...a: unknown[]) => init(...a), register: vi.fn(), capture: vi.fn() },
}));

const { PostHogProvider } = await import('../_PostHogProvider');

describe('PostHogProvider consent', () => {
  beforeEach(() => {
    init.mockClear();
    vi.stubEnv('NEXT_PUBLIC_POSTHOG_KEY', 'phc_test');
    localStorage.clear();
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    Object.defineProperty(navigator, 'doNotTrack', { value: null, configurable: true });
  });

  it('initializes analytics for a visitor who has not opted out', () => {
    render(<PostHogProvider>x</PostHogProvider>);
    expect(init).toHaveBeenCalledTimes(1);
  });

  it('never initializes when the browser sends Do-Not-Track', () => {
    Object.defineProperty(navigator, 'doNotTrack', { value: '1', configurable: true });
    render(<PostHogProvider>x</PostHogProvider>);
    expect(init).not.toHaveBeenCalled();
  });

  it('never initializes after the visitor opted out in settings', () => {
    localStorage.setItem('bw_analytics_opt_out', '1');
    render(<PostHogProvider>x</PostHogProvider>);
    expect(init).not.toHaveBeenCalled();
  });
});
