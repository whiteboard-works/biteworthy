/**
 * Phase 2.8 — web client for `POST /api/v1/ingestion_runs`.
 * Supports both source-URL and file-upload (PDF) modes.
 */

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface IngestionRunPayload {
  id: string;
  status: 'queued' | 'extracting' | 'resolving' | 'staged' | 'published' | 'failed';
  input_kind: 'photo' | 'url' | 'pdf';
  restaurant_id: string;
  state_history: Record<string, string>;
  failure_message: string | null;
  api_cost_cents: number;
  latency_ms: number | null;
  input_count: number;
  ingestion_items_count: number;
  created_at: string;
  updated_at: string;
}

export interface IngestionApiError {
  error: string;
  reason?: string;
  status?: number;
}

export class IngestionRequestError extends Error {
  status: number;
  body: IngestionApiError | null;
  constructor(status: number, body: IngestionApiError | null) {
    super(`Ingestion request failed: ${status}${body?.error ? ` (${body.error})` : ''}`);
    this.status = status;
    this.body = body;
  }
}

async function postIngestionRun(
  body: BodyInit,
  jwt: string,
  fetchImpl: typeof fetch,
  isMultipart: boolean,
): Promise<IngestionRunPayload> {
  const headers: Record<string, string> = { Authorization: `Bearer ${jwt}` };
  if (!isMultipart) headers['Content-Type'] = 'application/json';

  const res = await fetchImpl(`${API_BASE}/api/v1/ingestion_runs`, {
    method: 'POST',
    headers,
    body,
  });
  if (!res.ok) {
    let parsed: IngestionApiError | null = null;
    try {
      parsed = (await res.json()) as IngestionApiError;
    } catch {
      // ignore
    }
    throw new IngestionRequestError(res.status, parsed);
  }
  return (await res.json()) as IngestionRunPayload;
}

export async function ingestFromUrl(opts: {
  restaurantId: string;
  sourceUrl: string;
  jwt: string;
  fetchImpl?: typeof fetch;
}): Promise<IngestionRunPayload> {
  const { restaurantId, sourceUrl, jwt, fetchImpl = fetch } = opts;
  return postIngestionRun(
    JSON.stringify({ restaurant_id: restaurantId, source_url: sourceUrl }),
    jwt,
    fetchImpl,
    false,
  );
}

export async function ingestFromFile(opts: {
  restaurantId: string;
  file: File;
  jwt: string;
  fetchImpl?: typeof fetch;
}): Promise<IngestionRunPayload> {
  const { restaurantId, file, jwt, fetchImpl = fetch } = opts;
  const form = new FormData();
  form.append('restaurant_id', restaurantId);
  form.append('inputs[]', file, file.name);
  return postIngestionRun(form, jwt, fetchImpl, true);
}
