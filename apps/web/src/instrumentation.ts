/**
 * Next.js instrumentation hook (ADR 0009). `onRequestError` is called for
 * every error a route handler, server component render, or server action
 * lets escape; it is reported to PostHog error tracking from
 * `lib/posthog-server`. The import is deferred so the Edge bundle, which
 * also evaluates this file, never loads posthog-node.
 */
import type { Instrumentation } from 'next';

export const onRequestError: Instrumentation.onRequestError = async (err, request, context) => {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;
  const { reportRequestError } = await import('./lib/posthog-server');
  await reportRequestError(err, request, context);
};
