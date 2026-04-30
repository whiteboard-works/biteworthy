/**
 * Phase 4.8 — fetch the authenticated user's recent restaurant visits.
 * Mirrors apps/web/src/lib/history.ts; mobile uses the JWT directly
 * via the keychain (no Next proxy on mobile).
 */
const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface HistoryRestaurantCity {
  slug: string;
  name: string;
  region: string;
}

export interface HistoryRestaurant {
  id: string;
  slug: string;
  name: string;
  city: HistoryRestaurantCity;
}

export interface HistoryVisit {
  id: string;
  viewed_on: string;
  updated_at: string;
  items_visible_count: number;
  items_hidden_count: number;
  restaurant: HistoryRestaurant;
}

export interface HistoryResponse {
  visits: HistoryVisit[];
  total: number;
}

export class HistoryError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'HistoryError';
  }
}

export interface FetchHistoryOptions {
  limit?: number;
  offset?: number;
  fetchImpl?: typeof fetch;
}

export async function fetchHistory(
  jwt: string,
  opts: FetchHistoryOptions = {},
): Promise<HistoryResponse> {
  const { fetchImpl = fetch, limit, offset } = opts;
  const url = new URL(`${API_BASE}/api/v1/profile/history`);
  if (typeof limit === 'number') url.searchParams.set('limit', String(limit));
  if (typeof offset === 'number') url.searchParams.set('offset', String(offset));
  const res = await fetchImpl(url.toString(), {
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
  });
  if (!res.ok) throw new HistoryError(res.status, `fetchHistory failed: ${res.status}`);
  return (await res.json()) as HistoryResponse;
}
