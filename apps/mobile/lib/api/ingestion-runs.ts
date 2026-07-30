/**
 * Client for `POST /api/v1/ingestion_runs` (Phase 2.6).
 *
 * The screen at `app/ingest/index.tsx` calls `uploadIngestionRun` after
 * a multi-page camera capture. Auth header is the JWT the user got at
 * login (see Phase 1.1's signup/login flow); the endpoint requires
 * an admin user — Phase 4 will introduce a contributor role.
 */

import { API_BASE } from '../api-base';

export interface CapturedPage {
  /** A `file://` URI from `expo-camera`'s captured photo. */
  uri: string;
  /** "image/jpeg" or "image/png" */
  mimeType?: string;
}

export interface UploadOptions {
  restaurantId: string;
  pages: CapturedPage[];
  jwt: string;
  /** Override fetch — for tests; defaults to global fetch. */
  fetchImpl?: typeof fetch;
}

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

export class IngestionUploadError extends Error {
  status: number;
  body: unknown;
  constructor(status: number, body: unknown) {
    super(`Ingestion upload failed: ${status}`);
    this.status = status;
    this.body = body;
  }
}

export interface IngestionItemPayload {
  id: string;
  ingestion_run_id: string;
  item_id: string | null;
  name: string;
  description: string | null;
  section_name: string | null;
  decision: 'pending' | 'accepted' | 'rejected' | 'edited';
  decided_at: string | null;
  ingredients_payload: Array<{ slug: string; confidence: number }>;
  tags_payload: Array<{ slug: string; confidence: number }>;
  prices_payload: Array<{ size: string | null; price_cents: number | null }>;
  /**
   * Add-on/upsell lines nested under this dish; promoted to ItemModifiers on
   * accept. Optional: the app and API deploy independently, so an older API
   * may not send the field — always fall back to [].
   */
  addons_payload?: Array<{ name: string; price_cents: number | null; source: 'extract' | 'guard' }>;
  unresolved_ingredients: string[];
  unresolved_tags: string[];
}

export interface FetchOptions {
  jwt: string;
  fetchImpl?: typeof fetch;
}

/** Poll-friendly read of the run state. Use to wait until status === "staged". */
export async function getIngestionRun(
  runId: string,
  opts: FetchOptions,
): Promise<IngestionRunPayload> {
  const { jwt, fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/ingestion_runs/${runId}`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore
    }
    throw new IngestionUploadError(res.status, body);
  }
  return (await res.json()) as IngestionRunPayload;
}

/** List the staged items for the swipe deck. */
export async function listIngestionItems(
  runId: string,
  opts: FetchOptions,
): Promise<IngestionItemPayload[]> {
  const { jwt, fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/ingestion_runs/${runId}/items`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore
    }
    throw new IngestionUploadError(res.status, body);
  }
  const json = (await res.json()) as { items: IngestionItemPayload[] };
  return json.items;
}

export type Decision = 'accepted' | 'rejected' | 'edited';

export interface DecideOptions extends FetchOptions {
  runId: string;
  itemId: string;
  decision: Decision;
  /** Edit overrides — applied before promotion. Optional. */
  edits?: Partial<{
    name: string;
    description: string;
    ingredients_payload: Array<{ slug: string; confidence: number }>;
    tags_payload: Array<{ slug: string; confidence: number }>;
  }>;
}

/**
 * Update an ingestion item's decision. Accept fires promote! on the
 * Rails side (materializes a real Item). Edit overrides apply BEFORE
 * promotion, so the live Item carries the human's tweaks.
 */
export async function decideIngestionItem(
  opts: DecideOptions,
): Promise<IngestionItemPayload> {
  const { runId, itemId, decision, edits, jwt, fetchImpl = fetch } = opts;
  const res = await fetchImpl(
    `${API_BASE}/api/v1/ingestion_runs/${runId}/items/${itemId}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ decision, ...edits }),
    },
  );
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore
    }
    throw new IngestionUploadError(res.status, body);
  }
  return (await res.json()) as IngestionItemPayload;
}

export async function uploadIngestionRun(opts: UploadOptions): Promise<IngestionRunPayload> {
  const { restaurantId, pages, jwt, fetchImpl = fetch } = opts;

  if (pages.length === 0) {
    throw new Error('uploadIngestionRun requires at least one page');
  }

  const form = new FormData();
  form.append('restaurant_id', restaurantId);

  pages.forEach((page, i) => {
    // React Native's FormData accepts this Blob-like object shape — Node
    // tests patch FormData via undici/whatwg, so we keep the shape
    // standards-compliant.
    form.append('inputs[]', {
      uri: page.uri,
      name: `page-${i + 1}.jpg`,
      type: page.mimeType ?? 'image/jpeg',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
  });

  const res = await fetchImpl(`${API_BASE}/api/v1/ingestion_runs`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      // No Content-Type header — fetch will set the multipart boundary.
    },
    body: form as unknown as BodyInit,
  });

  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore
    }
    throw new IngestionUploadError(res.status, body);
  }

  return (await res.json()) as IngestionRunPayload;
}

/**
 * Phase 6.6 — human copy for the Phase 6.1 guardrails. Works for any
 * error carrying {status, body} (IngestionUploadError and
 * RestaurantCreateError both do).
 */
export function friendlyScanError(err: unknown): string {
  const e = err as { status?: number; body?: { error?: string; limit?: number } | null };
  if (typeof e?.status === 'number') {
    if (e.status === 429) {
      const limit = e.body?.limit;
      return `Daily scan limit reached${limit ? ` (${limit}/day)` : ''} — try again tomorrow.`;
    }
    if (e.status === 503) {
      return "Today's community scanning budget is used up — try again tomorrow.";
    }
    if (e.status === 403 && e.body?.error === 'forbidden_restaurant') {
      return "That restaurant is someone else's draft — pick a published restaurant or create your own.";
    }
  }
  return err instanceof Error ? err.message : String(err);
}
