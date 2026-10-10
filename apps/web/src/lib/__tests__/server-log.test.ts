import { afterEach, describe, expect, it, vi } from 'vitest';
import { serverLog } from '../server-log';

/**
 * Without a key (dev, CI, previews) a server log line still reaches the
 * console — Vercel's function log is the only sink then — and nothing is
 * built or sent. The OTLP path is exercised against production only.
 */
describe('serverLog without a PostHog key', () => {
  afterEach(() => vi.restoreAllMocks());

  it('mirrors each level to the console and does not throw', () => {
    vi.stubEnv('VERCEL_ENV', 'preview');
    vi.stubEnv('NEXT_PUBLIC_POSTHOG_KEY', '');
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});

    expect(() => serverLog.warn('upstream slow', { 'url.path': '/api/me' })).not.toThrow();
    expect(() =>
      serverLog.error('upstream failed', { 'http.response.status_code': 502 }),
    ).not.toThrow();

    expect(warn).toHaveBeenCalledWith('upstream slow', { 'url.path': '/api/me' });
    expect(error).toHaveBeenCalledWith('upstream failed', { 'http.response.status_code': 502 });
  });
});
