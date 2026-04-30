/**
 * Client for `POST /api/v1/ingestion_runs` (Phase 2.6).
 *
 * The screen at `app/ingest/index.tsx` calls `uploadIngestionRun` after
 * a multi-page camera capture. Auth header is the JWT the user got at
 * login (see Phase 1.1's signup/login flow); the endpoint requires
 * an admin user — Phase 4 will introduce a contributor role.
 */

const API_BASE =
  process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';

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
