/**
 * The Next server's side of PostHog (ADR 0009): a `posthog-node` client for
 * the errors route handlers and server renders throw, reported from
 * `src/instrumentation.ts`. Browser events have their own client in
 * `posthog-client.ts`; this one never sees a visitor.
 *
 * Each report carries the route and the request's path and method — and no
 * header, cookie, body, or identity. The session cookie is HttpOnly for a
 * reason, and a path is enough to find the handler.
 */
import type { Instrumentation } from 'next';
import { PostHog } from 'posthog-node';
import { maskPath } from './posthog-client';
import { POSTHOG_HOST, serverPostHogKey } from './posthog-config';

let client: PostHog | null | undefined;

/** The singleton, or null when there is no key (dev, CI, previews). */
export function serverPostHog(): PostHog | null {
  if (client !== undefined) return client;
  const key = serverPostHogKey();
  // Serverless: the function can be frozen the moment the response goes
  // out, so nothing may wait in a batch.
  client = key
    ? new PostHog(key, { host: POSTHOG_HOST, flushAt: 1, flushInterval: 0, disableGeoip: true })
    : null;
  return client;
}

type RequestInfo = Parameters<Instrumentation.onRequestError>[1];
type RequestContext = Parameters<Instrumentation.onRequestError>[2];

/**
 * The properties on a server `$exception`. Path only — the query can carry
 * a share token or `?profile=celiac` — and masked like the browser's page
 * views, so a diet page or a person's page is a route, not a value.
 */
export function requestErrorProperties(
  request: Pick<RequestInfo, 'path' | 'method'>,
  context: Pick<RequestContext, 'routerKind' | 'routePath' | 'routeType'> &
    Partial<Pick<RequestContext, 'renderSource'>>,
  err: unknown,
): Record<string, string> {
  const properties: Record<string, string> = {
    $exception_source: 'nextjs-server',
    'http.request.method': request.method,
    'url.path': maskPath(request.path.split(/[?#]/)[0] ?? ''),
    'next.router_kind': context.routerKind,
    'next.route_path': context.routePath,
    'next.route_type': context.routeType,
  };
  if (context.renderSource) properties['next.render_source'] = context.renderSource;
  const digest =
    typeof err === 'object' && err !== null && 'digest' in err ? err.digest : undefined;
  if (typeof digest === 'string') properties['error.digest'] = digest;
  return properties;
}

// What a message may quote and must not carry out: an email, a bearer token
// or JWT, a key with one of the prefixes the app holds, the password in a
// connection URL, an IPv4 address, and every query-string value (a share
// token, `?profile=celiac`). Mirrors `Telemetry::Scrub.text` in the API.
const SCRUBS: ReadonlyArray<[RegExp, string]> = [
  [/:\/\/[^/\s:@]+:[^@\s]+@/g, '://<redacted>@'],
  // An apostrophe is an ordinary query character ("Bob's"); a double quote
  // ends the value, because a quoted URL is how one appears in a message.
  [/([?&][^=&\s"]+=)[^&\s"]*/g, '$1<q>'],
  [/\b(sk-ant-|ghp_|github_pat_|apikey_|phx_|phs_|Bearer )\S+/g, '$1<redacted>'],
  [/\bre_[A-Za-z0-9_]{20,}/g, 're_<redacted>'],
  [/\beyJ[\w-]{10,}\.[\w-]+\.[\w-]+/g, '<jwt>'],
  [/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, '<ip>'],
  [/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, '<email>'],
];

export function scrubText(text: string): string {
  return SCRUBS.reduce((out, [pattern, replacement]) => out.replace(pattern, replacement), text);
}

const CAUSE_DEPTH = 3;

/**
 * The error as it may leave: same name and stack frames, the message
 * scrubbed, the cause chain the same to a depth. An upstream failure can
 * quote the response body it got, and a route handler's own message can
 * quote what it was handed; neither should reach a third party verbatim.
 */
export function sanitizeError(err: unknown, depth = 0): Error {
  const source = err instanceof Error ? err : new Error(String(err));
  const message = scrubText(source.message);
  const safe = new Error(message);
  safe.name = source.name;
  // The stack's first line repeats the message; the frames are ours.
  safe.stack = source.stack ? scrubText(source.stack) : undefined;
  if ('digest' in source && typeof source.digest === 'string') {
    Object.assign(safe, { digest: source.digest });
  }
  if (source.cause !== undefined && depth < CAUSE_DEPTH) {
    safe.cause = sanitizeError(source.cause, depth + 1);
  }
  return safe;
}

/** What `onRequestError` calls. Awaits the send: serverless, see above. */
export async function reportRequestError(
  err: unknown,
  request: RequestInfo,
  context: RequestContext,
): Promise<void> {
  const properties = requestErrorProperties(request, context, err);
  const safe = sanitizeError(err);
  // Vercel's own log keeps a line too, for the hour it keeps them — the
  // same scrubbed copy, so neither store holds what the other does not.
  console.error('[request-error]', properties, safe);
  const posthog = serverPostHog();
  if (!posthog) return;
  try {
    await posthog.captureExceptionImmediate(safe, undefined, properties);
  } catch (sendError) {
    console.error('[request-error] not reported to PostHog', sendError);
  }
}
