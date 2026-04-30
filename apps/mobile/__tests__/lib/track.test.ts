import { noopTracker, type AnalyticsClient } from '@biteworthy/analytics';
import { buildMobileTracker } from '../../lib/track';

const fakeClient = (): AnalyticsClient & { calls: Array<[string, unknown]> } => {
  const calls: Array<[string, unknown]> = [];
  return {
    calls,
    capture: (name, props) => {
      calls.push([name, props]);
    },
  };
};

describe('buildMobileTracker', () => {
  it('returns noopTracker when no apiKey is set', () => {
    expect(buildMobileTracker({ apiKey: null })).toBe(noopTracker);
  });

  it('returns noopTracker when the user has not explicitly opted in (App Store privacy posture)', () => {
    expect(buildMobileTracker({ apiKey: 'k', optedIn: false })).toBe(noopTracker);
  });

  it('still returns noopTracker when key + opt-in but no client is injected (Phase 5.8 ships abstraction-only)', () => {
    expect(buildMobileTracker({ apiKey: 'k', optedIn: true })).toBe(noopTracker);
  });

  it('returns a real tracker when apiKey + opt-in + client are all set', () => {
    const client = fakeClient();
    const tracker = buildMobileTracker({
      apiKey: 'k',
      optedIn: true,
      client,
    });

    tracker.track('menu_filtered', {
      restaurant_slug: 'cream-bean-berry',
      visible_count: 12,
      hidden_count: 2,
      filter_source: 'preset',
    });
    expect(client.calls).toHaveLength(1);
    expect(client.calls[0]![0]).toBe('menu_filtered');
  });
});
