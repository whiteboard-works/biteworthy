import { describe, expect, it } from 'vitest';
import { noopTracker, type AnalyticsClient } from '@biteworthy/analytics';
import { buildWebTracker } from '../track';

const fakeClient = (): AnalyticsClient & { calls: Array<[string, unknown]> } => {
  const calls: Array<[string, unknown]> = [];
  return {
    calls,
    capture: (name, props) => {
      calls.push([name, props]);
    },
  };
};

describe('buildWebTracker', () => {
  it('returns noopTracker when no apiKey is set (dev/CI)', () => {
    expect(buildWebTracker({ apiKey: null })).toBe(noopTracker);
  });

  it('returns noopTracker when Do-Not-Track is on', () => {
    expect(buildWebTracker({ apiKey: 'k', doNotTrack: true })).toBe(noopTracker);
  });

  it('returns noopTracker when the user opted out via localStorage', () => {
    expect(
      buildWebTracker({ apiKey: 'k', doNotTrack: false, optedOut: true }),
    ).toBe(noopTracker);
  });

  it('still returns noopTracker when apiKey is set but no client is injected (Phase 5.8 ships abstraction-only)', () => {
    expect(
      buildWebTracker({ apiKey: 'k', doNotTrack: false, optedOut: false }),
    ).toBe(noopTracker);
  });

  it('returns a real tracker when apiKey set + DNT off + opt-in + client injected', () => {
    const client = fakeClient();
    const tracker = buildWebTracker({
      apiKey: 'k',
      doNotTrack: false,
      optedOut: false,
      client,
    });

    tracker.track('app_open', { surface: 'web' });
    expect(client.calls).toEqual([['app_open', { surface: 'web' }]]);
  });
});
