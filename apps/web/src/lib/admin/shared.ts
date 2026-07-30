/**
 * Shared plumbing for the /admin data layer (`src/lib/admin/*`).
 *
 * Deliberate deviations from the flat-lib convention, surfaced in the
 * workstream plan: admin spans several domains, so its fetchers live
 * in this subdirectory, and they share ONE error class — admin pages
 * handle failures uniformly (401 → sign in again, 403/404 → access
 * lost, anything else → inline notice), so per-domain error subclasses
 * buy nothing here.
 */
export class AdminError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = 'AdminError';
    this.status = status;
  }
}

export async function getAdminJson<T>(path: string, fetchImpl: typeof fetch = fetch): Promise<T> {
  const res = await fetchImpl(path, { credentials: 'same-origin' });
  if (!res.ok) throw new AdminError(`Admin request failed (${res.status})`, res.status);
  return (await res.json()) as T;
}

/** Human copy for a failed admin fetch. */
export function friendlyAdminError(err: unknown): string {
  if (err instanceof AdminError) {
    if (err.status === 401) return 'You are signed out — sign in again to continue.';
    if (err.status === 403 || err.status === 404) {
      return 'Admin access is gone — your account may have been changed.';
    }
  }
  return 'Something went wrong loading admin data. Try again.';
}
