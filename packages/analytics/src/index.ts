/**
 * BiteWorthy analytics — typed Tracker abstraction shared by web +
 * mobile.
 *
 * Phase 5.8 ships the abstraction + the canonical event taxonomy;
 * the actual posthog-js / posthog-react-native install + the 9
 * call-site instrumentations are a follow-up PR (see
 * `docs/analytics.md` + `docs/adr/0006-analytics.md`).
 *
 * Design choices that matter:
 *
 *   1. **No vendor SDK as a hard dep.** This package speaks only to
 *      the `AnalyticsClient` interface — apps inject `posthog-js` or
 *      `posthog-react-native` (or any other SDK; or `null`) at the
 *      tracker boundary. Lets us swap providers in one place if
 *      PostHog ever bites cost-wise.
 *
 *   2. **Stable event names live in `EVENTS`.** Adding a new event
 *      means adding it to that map; misspelled call-sites become
 *      compile errors instead of split funnels in the dashboard.
 *
 *   3. **Payload shape per event is type-checked.** `track('menu_filtered',
 *      { restaurant_slug: ... })` enforces the prop names. The
 *      `EVENT_PROPS` map below is the single source of truth, mirroring
 *      `docs/analytics.md`.
 *
 *   4. **`noopTracker` is the safe default.** Returned when
 *      `POSTHOG_KEY` is unset OR Do-Not-Track is on OR the user opted
 *      out. Calls into it are zero-cost — never undefined-method-throws,
 *      never sends bytes.
 */

// ─── Event taxonomy ────────────────────────────────────────────────

/**
 * Canonical event names. The funnel:
 *
 *   app_open → profile_set → menu_filtered → restaurant_tap
 *
 * Plus the per-engagement events (review_posted, suggestion_submitted,
 * restaurant_claimed, share_link_copied, filter_changed).
 *
 * Names are snake_case to match PostHog's funnel-builder UI conventions.
 */
export const EVENTS = {
  app_open:             'app_open',
  profile_set:          'profile_set',
  menu_filtered:        'menu_filtered',
  restaurant_tap:       'restaurant_tap',
  filter_changed:       'filter_changed',
  review_posted:        'review_posted',
  share_link_copied:    'share_link_copied',
  restaurant_claimed:   'restaurant_claimed',
  suggestion_submitted: 'suggestion_submitted',
} as const;

export type EventName = keyof typeof EVENTS;

/**
 * Per-event payload schemas. Keep these stable — the dashboard funnel
 * + retention queries depend on field names. New optional fields are
 * fine; renames break dashboards.
 *
 * Mirrored in `docs/analytics.md` (the human-readable doc); when one
 * changes, change the other in the same PR.
 */
export interface EventPropsMap {
  app_open: {
    /** Web | iOS | Android. Set by the app boundary. */
    surface: 'web' | 'ios' | 'android';
    /** Sticky once set — same anonymous id across sessions until logout. */
    distinct_id?: string;
  };
  profile_set: {
    preset_slug: string | null;
    avoid_ingredient_count: number;
    avoid_tag_count: number;
    strictness: 'relaxed' | 'balanced' | 'strict';
  };
  menu_filtered: {
    restaurant_slug: string;
    visible_count: number;
    hidden_count: number;
    /** preset | user_profile | profile_token | none */
    filter_source: string;
  };
  restaurant_tap: {
    restaurant_slug: string;
    /** Where the tap came from: home, search, durango_diet, history. */
    from: string;
  };
  filter_changed: {
    /** What changed: strictness | preset | manual_avoid | manual_unavoid. */
    kind: string;
    /** Old + new values — strings so the funnel UI can groupby. */
    from?: string;
    to?: string;
  };
  review_posted: {
    item_slug: string;
    restaurant_slug: string;
    rating: number;
    has_photo: boolean;
  };
  share_link_copied: {
    restaurant_slug: string;
    /** Whether the user tapped Share or had to copy the URL. */
    via: 'native_share' | 'clipboard' | 'prompt_fallback';
  };
  restaurant_claimed: {
    restaurant_slug: string;
    /** auto_acceptable (domain match) or admin_review. */
    decision: string;
  };
  suggestion_submitted: {
    item_slug: string;
    restaurant_slug: string;
    /** add_ingredient | rename | etc. — see Phase 4.10. */
    kind: string;
  };
}

// ─── Client interface (injected; not a hard dep) ───────────────────

/**
 * Minimum surface BiteWorthy needs from any analytics SDK. PostHog's
 * web + RN clients both satisfy this naturally; switching providers
 * means writing an adapter to this shape.
 */
export interface AnalyticsClient {
  capture(eventName: string, props?: Record<string, unknown>): void;
  identify?(distinctId: string, props?: Record<string, unknown>): void;
  reset?(): void;
}

// ─── Tracker — the surface app code calls ──────────────────────────

export interface Tracker {
  /**
   * Type-safe per-event capture. Use `EVENTS` keys; the props shape
   * is enforced by `EventPropsMap`.
   */
  track<K extends EventName>(name: K, props: EventPropsMap[K]): void;

  /** Same identity across sessions until reset(). */
  identify(distinctId: string, props?: Record<string, unknown>): void;

  /** Logout / signout — clears the distinct_id. */
  reset(): void;
}

/**
 * No-op tracker. Used when:
 *   - POSTHOG_KEY is unset (dev/CI/no-credentials)
 *   - Do-Not-Track is on (browser)
 *   - User opted out via in-app analytics toggle
 *
 * Zero allocations on call; safe to spread through hot paths.
 */
export const noopTracker: Tracker = {
  track: () => {},
  identify: () => {},
  reset: () => {},
};

interface CreateTrackerOptions {
  client: AnalyticsClient;
}

/**
 * Build a Tracker that delegates to an injected SDK. The app
 * boundary (apps/web/src/lib/track.ts and apps/mobile/lib/track.ts)
 * decides whether to construct one or fall back to `noopTracker`.
 */
export function createTracker({ client }: CreateTrackerOptions): Tracker {
  return {
    track(name, props) {
      // Cast to the SDK's loose Record signature — the type narrowing
      // happens at the call site via EventPropsMap.
      client.capture(name, props as Record<string, unknown>);
    },
    identify(distinctId, props) {
      client.identify?.(distinctId, props);
    },
    reset() {
      client.reset?.();
    },
  };
}
