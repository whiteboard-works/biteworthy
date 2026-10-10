/**
 * Server-side log lines that outlive the function that wrote them (ADR
 * 0009). Vercel keeps a function's console output for about an hour; this
 * also sends each line to PostHog Logs over OTLP, where the API's logs go
 * too, so one search covers a request from the browser's proxy call to the
 * Rails handler.
 *
 * Use it for what someone will want to find later: an upstream failure, a
 * clamped error, a refused request. Not for tracing a happy path — every
 * line costs a request from a serverless function.
 */
import { after } from 'next/server';
import { SeverityNumber } from '@opentelemetry/api-logs';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { BatchLogRecordProcessor, LoggerProvider } from '@opentelemetry/sdk-logs';
import { POSTHOG_HOST, serverPostHogKey } from './posthog-config';
import { scrubText } from './posthog-server';

export type LogAttributes = Record<string, string | number | boolean>;

const SERVICE_NAME = 'biteworthy-web';

let provider: LoggerProvider | null | undefined;

function loggerProvider(): LoggerProvider | null {
  if (provider !== undefined) return provider;
  const key = serverPostHogKey();
  if (!key) return (provider = null);
  provider = new LoggerProvider({
    resource: resourceFromAttributes({
      'service.name': SERVICE_NAME,
      'deployment.environment': process.env.VERCEL_ENV ?? process.env.NODE_ENV ?? 'unknown',
    }),
    processors: [
      new BatchLogRecordProcessor({
        exporter: new OTLPLogExporter({
          url: `${POSTHOG_HOST}/i/v1/logs`,
          headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        }),
      }),
    ],
  });
  return provider;
}

function emit(
  severityNumber: SeverityNumber,
  severityText: 'INFO' | 'WARN' | 'ERROR',
  body: string,
  attributes: LogAttributes,
): void {
  const active = loggerProvider();
  if (!active) return;
  try {
    active.getLogger(SERVICE_NAME).emit({ severityNumber, severityText, body, attributes });
    scheduleFlush(active);
  } catch {
    // Logging must never be what breaks a request.
  }
}

// The batch processor flushes on a timer the function may never live to
// see. Inside a request, `after` runs once the response is sent; outside
// one (a background import, a test) it throws, and the flush is simply
// started. One flush is pending at a time: a burst of lines (every proxied
// request failing while Rails is down) is one export, not one per line.
let pendingFlush: Promise<void> | null = null;

function scheduleFlush(active: LoggerProvider): void {
  if (pendingFlush) return;
  pendingFlush = new Promise<void>((resolve) => {
    const flush = (): Promise<void> =>
      active
        .forceFlush()
        .catch(() => {})
        .finally(() => {
          pendingFlush = null;
          resolve();
        });
    try {
      after(flush);
    } catch {
      void flush();
    }
  });
}

// Scrubbed once, before either sink: the console line Vercel keeps and the
// OTLP record carry the same text, with the same gaps the exception path
// leaves (a quoted URL loses its query values, an address or a key goes).
function scrubbed(message: string, attributes: LogAttributes): [string, LogAttributes] {
  const safe: LogAttributes = {};
  for (const [key, value] of Object.entries(attributes)) {
    safe[key] = typeof value === 'string' ? scrubText(value) : value;
  }
  return [scrubText(message), safe];
}

export const serverLog = {
  info(message: string, attributes: LogAttributes = {}): void {
    const [body, safe] = scrubbed(message, attributes);
    console.info(body, safe);
    emit(SeverityNumber.INFO, 'INFO', body, safe);
  },
  warn(message: string, attributes: LogAttributes = {}): void {
    const [body, safe] = scrubbed(message, attributes);
    console.warn(body, safe);
    emit(SeverityNumber.WARN, 'WARN', body, safe);
  },
  error(message: string, attributes: LogAttributes = {}): void {
    const [body, safe] = scrubbed(message, attributes);
    console.error(body, safe);
    emit(SeverityNumber.ERROR, 'ERROR', body, safe);
  },
};
