/**
 * The scan screen's calls: start a scan, poll it, publish what the person
 * accepted. All three go through `/api/scans*`, which proxies to the
 * Rails scan door with the session cookie — a row read per poll, never a
 * model call.
 */
import type {
  ScanAccepted,
  ScanDish,
  ScanRejected,
  ScanStarted,
  ScanStatus,
} from '@biteworthy/api-types';
import { NotSignedInError, uploadAttachment } from './chat';

export type { ScanAccepted, ScanDish, ScanRejected, ScanStarted, ScanStatus };
export { NotSignedInError, uploadAttachment };

/** Carries the API's machine code (e.g. `quota_exceeded`) beside the sentence. */
export class ScanError extends Error {
  constructor(
    message: string,
    readonly code: string | null,
  ) {
    super(message);
    this.name = 'ScanError';
  }
}

async function json<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { credentials: 'same-origin', ...init });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) {
    let body: { error?: string; code?: string } = {};
    try {
      body = (await res.json()) as typeof body;
    } catch {
      // Non-JSON error bodies fall through to the status line.
    }
    throw new ScanError(body.error ?? `Request failed (${res.status})`, body.code ?? null);
  }
  return (await res.json()) as T;
}

export type ScanSource = { attachmentIds: string[] } | { sourceUrl: string };

export function startScan(restaurant: string, source: ScanSource): Promise<ScanStarted> {
  const body =
    'attachmentIds' in source
      ? { restaurant, attachment_ids: source.attachmentIds }
      : { restaurant, source_url: source.sourceUrl };
  return json('/api/scans', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

export function getScan(id: string): Promise<ScanStatus> {
  return json(`/api/scans/${encodeURIComponent(id)}`, { cache: 'no-store' });
}

export function acceptScan(id: string, itemIds: string[]): Promise<ScanAccepted> {
  return json(`/api/scans/${encodeURIComponent(id)}/accept`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ item_ids: itemIds }),
  });
}

/** "Not on the menu" — kept for the audit trail, counted toward publishing. */
export function rejectScan(id: string, itemIds: string[]): Promise<ScanRejected> {
  return json(`/api/scans/${encodeURIComponent(id)}/reject`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ item_ids: itemIds }),
  });
}
