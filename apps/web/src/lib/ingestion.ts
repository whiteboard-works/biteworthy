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
  /**
   * The run reaches `staged` on deterministic matches alone; the AI
   * gap-fill pass may still be appending suggestions in the background.
   */
  enrichment_status: 'pending' | 'completed' | 'failed';
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

/** Phase 6.5 — community restaurant creation + the verify flow. */

export interface DuplicateCandidate {
  id: string;
  slug: string;
  name: string;
  status: string;
  street: string | null;
}

export interface CreatedRestaurant {
  id: string;
  slug: string;
  name: string;
  status: string;
}

export type CreateRestaurantResult =
  | { kind: 'created'; restaurant: CreatedRestaurant }
  | { kind: 'duplicates'; candidates: DuplicateCandidate[] };

export async function createRestaurant(opts: {
  name: string;
  citySlug: string;
  street?: string;
  postalCode?: string;
  force?: boolean;
  fetchImpl?: typeof fetch;
}): Promise<CreateRestaurantResult> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/restaurants', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({
      name: opts.name,
      city_slug: opts.citySlug,
      street: opts.street,
      postal_code: opts.postalCode,
      force: opts.force ? 'true' : undefined,
    }),
  });

  if (res.status === 409) {
    const body = (await res.json()) as { candidates: DuplicateCandidate[] };
    return { kind: 'duplicates', candidates: body.candidates ?? [] };
  }
  if (!res.ok) {
    let parsed: IngestionApiError | null = null;
    try {
      parsed = (await res.json()) as IngestionApiError;
    } catch {
      // ignore
    }
    throw new IngestionRequestError(res.status, parsed);
  }
  return { kind: 'created', restaurant: (await res.json()) as CreatedRestaurant };
}

export interface IngestionItemPayload {
  id: string;
  ingestion_run_id: string;
  item_id: string | null;
  /** Flat index within the run's extraction order — used to keep verify stable. */
  position: number | null;
  name: string | null;
  description: string | null;
  section_name: string | null;
  decision: 'pending' | 'accepted' | 'rejected' | 'edited';
  decided_at: string | null;
  ingredients_payload: Array<{ slug: string; confidence: number }>;
  tags_payload: Array<{ slug: string; confidence: number }>;
  prices_payload: Array<{ size: string | null; price_cents: number }>;
  unresolved_ingredients: string[];
  unresolved_tags: string[];
}

async function getJson<T>(path: string, fetchImpl: typeof fetch): Promise<T> {
  const res = await fetchImpl(path, { credentials: 'same-origin' });
  if (!res.ok) {
    let parsed: IngestionApiError | null = null;
    try {
      parsed = (await res.json()) as IngestionApiError;
    } catch {
      // ignore
    }
    throw new IngestionRequestError(res.status, parsed);
  }
  return (await res.json()) as T;
}

export async function fetchRun(
  runId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<IngestionRunPayload> {
  return getJson<IngestionRunPayload>(
    `/api/ingestion_runs/${encodeURIComponent(runId)}`,
    fetchImpl,
  );
}

export async function fetchRunItems(
  runId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<IngestionItemPayload[]> {
  const body = await getJson<{ items: IngestionItemPayload[] }>(
    `/api/ingestion_runs/${encodeURIComponent(runId)}/items`,
    fetchImpl,
  );
  return body.items;
}

export async function decideRunItem(opts: {
  runId: string;
  itemId: string;
  /** `pending` is Undo — reverts a decision (and un-promotes if it went live). */
  decision: 'accepted' | 'rejected' | 'pending';
  fetchImpl?: typeof fetch;
}): Promise<IngestionItemPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(
    `/api/ingestion_runs/${encodeURIComponent(opts.runId)}/items/${encodeURIComponent(opts.itemId)}`,
    {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify({ decision: opts.decision }),
    },
  );
  if (!res.ok) {
    let parsed: IngestionApiError | null = null;
    try {
      parsed = (await res.json()) as IngestionApiError;
    } catch {
      // ignore
    }
    throw new IngestionRequestError(res.status, parsed);
  }
  return (await res.json()) as IngestionItemPayload;
}

/** Bulk-accept every pending item on a run (Accept All). Returns all items. */
export async function acceptAllRunItems(
  runId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<IngestionItemPayload[]> {
  const res = await fetchImpl(`/api/ingestion_runs/${encodeURIComponent(runId)}/items/accept_all`, {
    method: 'POST',
    credentials: 'same-origin',
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
  const body = (await res.json()) as { items: IngestionItemPayload[] };
  return body.items;
}

/**
 * Human messages for the Phase 6.1 guardrails. Anything unmapped
 * falls back to the raw error message.
 */
export function friendlyIngestionError(err: unknown): string {
  if (err instanceof IngestionRequestError) {
    if (err.status === 429) {
      const limit = (err.body as { limit?: number } | null)?.limit;
      return `Daily scan limit reached${limit ? ` (${limit}/day)` : ''} — try again tomorrow.`;
    }
    if (err.status === 503) {
      return "Today's community scanning budget is used up — try again tomorrow.";
    }
    if (err.status === 403 && err.body?.error === 'forbidden_restaurant') {
      return "That restaurant is someone else's draft — pick a published restaurant or create your own.";
    }
  }
  return err instanceof Error ? err.message : String(err);
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
  files: File[];
  fetchImpl?: typeof fetch;
}): Promise<IngestionRunPayload> {
  const { restaurantId, files, fetchImpl = fetch } = opts;
  const form = new FormData();
  form.append('restaurant_id', restaurantId);
  // One run can carry several pages — each menu page/photo becomes an
  // `inputs[]` entry (the Rails endpoint caps this at INGESTION_MAX_INPUT_FILES).
  for (const file of files) {
    form.append('inputs[]', file, file.name);
  }
  return postIngestionRun(form, fetchImpl, true);
}

export async function ingestFromText(opts: {
  restaurantId: string;
  sourceText: string;
  fetchImpl?: typeof fetch;
}): Promise<IngestionRunPayload> {
  const { restaurantId, sourceText, fetchImpl = fetch } = opts;
  return postIngestionRun(
    JSON.stringify({ restaurant_id: restaurantId, source_text: sourceText }),
    fetchImpl,
    false,
  );
}
