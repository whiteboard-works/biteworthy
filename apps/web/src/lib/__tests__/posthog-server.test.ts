import { describe, expect, it } from 'vitest';
import { afterEach, vi } from 'vitest';
import {
  reportRequestError,
  requestErrorProperties,
  sanitizeError,
  scrubText,
} from '../posthog-server';

const context = {
  routerKind: 'App Router' as const,
  routePath: '/app/durango/[diet]',
  routeType: 'render' as const,
  renderSource: 'react-server-components' as const,
};

/**
 * A server `$exception` names the route and the request's shape — never a
 * header, a cookie, a body, or a query string. The query is where a share
 * token or `?profile=celiac` travels, and the path segments that name a
 * diet or a person are masked the way page views already are.
 */
describe('requestErrorProperties', () => {
  it('keeps the route and the masked path, drops the query', () => {
    const props = requestErrorProperties(
      { method: 'GET', path: '/durango/celiac?profile=celiac#top' },
      context,
      new Error('boom'),
    );
    expect(props).toEqual({
      $exception_source: 'nextjs-server',
      'http.request.method': 'GET',
      'url.path': '/durango/:diet',
      'next.router_kind': 'App Router',
      'next.route_path': '/app/durango/[diet]',
      'next.route_type': 'render',
      'next.render_source': 'react-server-components',
    });
  });

  it('masks a person out of a profile path, web or API', () => {
    expect(
      requestErrorProperties({ method: 'GET', path: '/u/skylar' }, context, {})['url.path'],
    ).toBe('/u/:handle');
    expect(
      requestErrorProperties({ method: 'GET', path: '/api/v1/users/skylar' }, context, {})[
        'url.path'
      ],
    ).toBe('/api/v1/users/:handle');
  });

  it("carries React's digest when the thrown value has one", () => {
    const err = Object.assign(new Error('x'), { digest: 'NEXT_NOT_FOUND' });
    const props = requestErrorProperties({ method: 'POST', path: '/api/chat' }, context, err);
    expect(props['error.digest']).toBe('NEXT_NOT_FOUND');
  });

  it('never includes headers, even when handed them', () => {
    const props = requestErrorProperties(
      { method: 'GET', path: '/x', headers: { cookie: 'bw_session=secret' } } as never,
      context,
      new Error('x'),
    );
    expect(JSON.stringify(props)).not.toContain('bw_session');
  });
});

/**
 * The exception itself is what posthog-node serializes, message and cause
 * chain included, so a route handler that quotes an upstream body or an
 * address in its error must have that quote removed before it is sent.
 */
describe('sanitizeError', () => {
  it('scrubs the message and the stack header, keeps the name and the frames', () => {
    const err = new TypeError(
      'upstream said: user someone@example.com, token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig',
    );
    const safe = sanitizeError(err);
    expect(safe.name).toBe('TypeError');
    expect(safe.message).toBe('upstream said: user <email>, token <jwt>');
    expect(safe.stack).not.toContain('someone@example.com');
    expect(safe.stack).toContain('posthog-server.test.ts');
  });

  it('walks the cause chain and keeps the digest', () => {
    const cause = new Error('connect ECONNREFUSED 10.0.0.7:3000');
    const err = Object.assign(new Error('fetch failed', { cause }), { digest: 'abc123' });
    const safe = sanitizeError(err) as Error & { digest?: string };
    expect(safe.digest).toBe('abc123');
    expect((safe.cause as Error).message).toBe('connect ECONNREFUSED <ip>:3000');
  });

  it('turns a thrown non-error into an Error with a scrubbed message', () => {
    expect(sanitizeError('Bearer abc.def.ghi leaked').message).toBe('Bearer <redacted> leaked');
  });
});

describe('scrubText', () => {
  it('blanks every query value, as the API scrubber does', () => {
    expect(
      scrubText(
        'upstream 500 for /items?profile=celiac&strictness=strict#top and /r/x?p=eyJhIjoxfQ',
      ),
    ).toBe('upstream 500 for /items?profile=<q>&strictness=<q> and /r/x?p=<q>');
  });

  it('redacts the credential shapes the API scrubber does', () => {
    expect(
      scrubText('postgresql://u:hunter2@db/x sk-ant-api03-zzz re_D4Tw9LZ1JNdEy5SCZfxVqtXXEZN'),
    ).toBe('postgresql://<redacted>@db/x sk-ant-<redacted> re_<redacted>');
  });
});

describe('reportRequestError', () => {
  afterEach(() => vi.restoreAllMocks());

  it('writes the scrubbed error to the console, never the original', async () => {
    vi.stubEnv('VERCEL_ENV', 'preview');
    vi.stubEnv('NEXT_PUBLIC_POSTHOG_KEY', '');
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});

    await reportRequestError(
      new Error('upstream 422: {"email":"someone@example.com"}'),
      { path: '/api/me', method: 'GET', headers: {} },
      { routerKind: 'App Router', routePath: '/api/me', routeType: 'route' } as never,
    );

    const logged = JSON.stringify(error.mock.calls.map((call) => call.map(String)));
    expect(logged).toContain('<email>');
    expect(logged).not.toContain('someone@example.com');
  });
});
