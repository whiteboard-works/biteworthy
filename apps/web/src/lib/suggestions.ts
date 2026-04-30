/**
 * Phase 4.10 — community-edit suggestions client.
 *
 * createSuggestion: anyone (signed in or not). Posts to the Next
 * proxy at /api/items/:id/suggestions which forwards the cookie's
 * JWT when present so the suggestion attributes properly.
 *
 * fetchSuggestionsForRestaurant + decideSuggestion: owner / admin
 * only. The Next proxy gates on the cookie session.
 */

export const SUGGESTION_KINDS = [
  'add_ingredient',
  'remove_ingredient',
  'add_tag',
  'remove_tag',
  'rename',
] as const;
export type SuggestionKind = (typeof SUGGESTION_KINDS)[number];

export type SuggestionStatus = 'pending' | 'accepted' | 'rejected';

export interface SuggestionSubmitter {
  id: string;
  handle: string | null;
  display_name: string | null;
}

export interface SuggestionPayload {
  id: string;
  kind: SuggestionKind | string;
  status: SuggestionStatus | string;
  payload: Record<string, unknown>;
  created_at: string;
  resolved_at: string | null;
  item: { id: string; name: string; restaurant_id: string } | null;
  submitter: SuggestionSubmitter | null;
}

export class SuggestionError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly kind?: string,
  ) {
    super(message);
    this.name = 'SuggestionError';
  }
}

export interface NewSuggestion {
  kind: SuggestionKind;
  payload: Record<string, unknown>;
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export async function createSuggestion(
  itemId: string,
  body: NewSuggestion,
  opts: FetchOptions = {},
): Promise<SuggestionPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/items/${encodeURIComponent(itemId)}/suggestions`, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw await suggestionError(res, `createSuggestion ${itemId}`);
  return (await res.json()) as SuggestionPayload;
}

export async function fetchSuggestionsForRestaurant(
  slug: string,
  opts: FetchOptions = {},
): Promise<{ suggestions: SuggestionPayload[] }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/restaurants/${encodeURIComponent(slug)}/suggestions`, {
    credentials: 'same-origin',
  });
  if (!res.ok) throw await suggestionError(res, `fetchSuggestions ${slug}`);
  return (await res.json()) as { suggestions: SuggestionPayload[] };
}

export async function decideSuggestion(
  id: string,
  decision: 'accepted' | 'rejected',
  opts: FetchOptions = {},
): Promise<SuggestionPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/suggestions/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ decision }),
  });
  if (!res.ok) throw await suggestionError(res, `decideSuggestion ${id}`);
  return (await res.json()) as SuggestionPayload;
}

async function suggestionError(res: Response, label: string): Promise<SuggestionError> {
  let body: { error?: string; kind?: string } | null = null;
  try {
    body = (await res.json()) as { error?: string; kind?: string };
  } catch {
    // ignore
  }
  return new SuggestionError(
    res.status,
    `${label} failed: ${res.status}${body?.error ? ` — ${body.error}` : ''}`,
    body?.kind,
  );
}
