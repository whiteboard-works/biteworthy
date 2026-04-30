import { describe, expect, it, vi } from 'vitest';
import {
  EVENTS,
  createTracker,
  noopTracker,
  type AnalyticsClient,
} from '../index';

describe('EVENTS taxonomy', () => {
  it('lists every funnel event the docs/analytics.md claims', () => {
    expect(Object.keys(EVENTS).sort()).toEqual(
      [
        'app_open',
        'profile_set',
        'menu_filtered',
        'restaurant_tap',
        'filter_changed',
        'review_posted',
        'share_link_copied',
        'restaurant_claimed',
        'suggestion_submitted',
      ].sort(),
    );
  });

  it('values are the same as keys (no aliasing)', () => {
    for (const [k, v] of Object.entries(EVENTS)) {
      expect(v).toBe(k);
    }
  });
});

describe('noopTracker', () => {
  it('never throws — safe to spread through hot paths', () => {
    expect(() => {
      noopTracker.track('app_open', { surface: 'web' });
      noopTracker.track('menu_filtered', {
        restaurant_slug: 's',
        visible_count: 3,
        hidden_count: 1,
        filter_source: 'preset',
      });
      noopTracker.identify('u-1');
      noopTracker.reset();
    }).not.toThrow();
  });
});

describe('createTracker', () => {
  function fakeClient(): AnalyticsClient & {
    captures: Array<[string, Record<string, unknown> | undefined]>;
    identifies: Array<[string, Record<string, unknown> | undefined]>;
    resets: number;
  } {
    const captures: Array<[string, Record<string, unknown> | undefined]> = [];
    const identifies: Array<[string, Record<string, unknown> | undefined]> = [];
    let resets = 0;
    return {
      captures,
      identifies,
      get resets() {
        return resets;
      },
      capture: (name, props) => {
        captures.push([name, props]);
      },
      identify: (id, props) => {
        identifies.push([id, props]);
      },
      reset: () => {
        resets += 1;
      },
    };
  }

  it('forwards track() to client.capture() with the canonical event name + props', () => {
    const client = fakeClient();
    const tracker = createTracker({ client });

    tracker.track('menu_filtered', {
      restaurant_slug: 'cream-bean-berry',
      visible_count: 12,
      hidden_count: 3,
      filter_source: 'preset',
    });

    expect(client.captures).toHaveLength(1);
    expect(client.captures[0]![0]).toBe('menu_filtered');
    expect(client.captures[0]![1]).toEqual({
      restaurant_slug: 'cream-bean-berry',
      visible_count: 12,
      hidden_count: 3,
      filter_source: 'preset',
    });
  });

  it('forwards identify() + reset() through the optional client methods', () => {
    const client = fakeClient();
    const tracker = createTracker({ client });

    tracker.identify('user-123', { handle: 'skylar' });
    tracker.reset();

    expect(client.identifies).toEqual([['user-123', { handle: 'skylar' }]]);
    expect(client.resets).toBe(1);
  });

  it('tolerates clients that omit identify / reset (only capture is required)', () => {
    const captureOnly: AnalyticsClient = { capture: vi.fn() };
    const tracker = createTracker({ client: captureOnly });

    expect(() => {
      tracker.identify('u');
      tracker.reset();
    }).not.toThrow();
  });
});
