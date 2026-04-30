/**
 * Phase 2.8 + 4.1 — web client for ingestion runs.
 *
 * Posts to the Next proxy at `/api/ingestion_runs` (which reads the
 * `bw_session` cookie and forwards to Rails as a Bearer header), so
 * the browser never needs to know the JWT.
 */

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
  fetchImpl: typeof fetch,
  isMultipart: boolean,
): Promise<IngestionRunPayload> {
  const headers: Record<string, string> = {};
  if (!isMultipart) headers['Content-Type'] = 'application/json';

  const res = await fetchImpl('/api/ingestion_runs', {
    method: 'POST',
    headers,
    credentials: 'same-origin',
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
  fetchImpl?: typeof fetch;
}): Promise<IngestionRunPayload> {
  const { restaurantId, sourceUrl, fetchImpl = fetch } = opts;
  return postIngestionRun(
    JSON.stringify({ restaurant_id: restaurantId, source_url: sourceUrl }),
    fetchImpl,
    false,
  );
}

export async function ingestFromFile(opts: {
  restaurantId: string;
  file: File;
  fetchImpl?: typeof fetch;
}): Promise<IngestionRunPayload> {
  const { restaurantId, file, fetchImpl = fetch } = opts;
  const form = new FormData();
  form.append('restaurant_id', restaurantId);
  form.append('inputs[]', file, file.name);
  return postIngestionRun(form, fetchImpl, true);
}
