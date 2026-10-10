import { describe, expect, it } from 'vitest';
import { browserPostHogKey, POSTHOG_PROJECT_TOKEN, serverPostHogKey } from '../posthog-config';

/**
 * ADR 0009 — the production hosts always report to project 652080, and
 * nowhere else reports unless told to. A stale `NEXT_PUBLIC_POSTHOG_KEY`
 * in a dashboard must not be able to point production somewhere else,
 * and a developer's laptop must not send events by default.
 */
describe('browserPostHogKey', () => {
  it('uses the project token on the production hosts, whatever the env says', () => {
    expect(browserPostHogKey('bite-worthy.com', 'phc_stale')).toBe(POSTHOG_PROJECT_TOKEN);
    expect(browserPostHogKey('www.bite-worthy.com', undefined)).toBe(POSTHOG_PROJECT_TOKEN);
  });

  it('falls back to the env var elsewhere, and to nothing without one', () => {
    expect(browserPostHogKey('localhost', 'phc_preview')).toBe('phc_preview');
    expect(browserPostHogKey('biteworthy-git-x.vercel.app', '')).toBeUndefined();
    expect(browserPostHogKey('localhost', undefined)).toBeUndefined();
  });

  it('does not treat a lookalike host as production', () => {
    expect(browserPostHogKey('bite-worthy.com.evil.example', undefined)).toBeUndefined();
    expect(browserPostHogKey('staging.bite-worthy.com', undefined)).toBeUndefined();
  });
});

describe('serverPostHogKey', () => {
  it("uses the project token on Vercel's production deployment", () => {
    expect(
      serverPostHogKey({ VERCEL_ENV: 'production', NEXT_PUBLIC_POSTHOG_KEY: 'phc_stale' }),
    ).toBe(POSTHOG_PROJECT_TOKEN);
  });

  it('falls back to the env var on previews and locally', () => {
    expect(serverPostHogKey({ VERCEL_ENV: 'preview', NEXT_PUBLIC_POSTHOG_KEY: 'phc_p' })).toBe(
      'phc_p',
    );
    expect(serverPostHogKey({})).toBeUndefined();
  });
});
