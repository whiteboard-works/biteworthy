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
  /** The Rails `{ error: "…" }` code, when the body carried one. */
  readonly code?: string;
  /** The full parsed error body (e.g. a 409's reference counts). */
  readonly body?: Record<string, unknown>;

  constructor(message: string, status: number, code?: string, body?: Record<string, unknown>) {
    super(message);
    this.name = 'AdminError';
    this.status = status;
    this.code = code;
    this.body = body;
  }
}

export async function toAdminError(res: Response): Promise<AdminError> {
  let code: string | undefined;
  let body: Record<string, unknown> | undefined;
  try {
    body = (await res.json()) as Record<string, unknown>;
    code = typeof body.error === 'string' ? body.error : undefined;
  } catch {
    // non-JSON body — status alone is enough
  }
  return new AdminError(`Admin request failed (${res.status})`, res.status, code, body);
}

export async function getAdminJson<T>(path: string, fetchImpl: typeof fetch = fetch): Promise<T> {
  const res = await fetchImpl(path, { credentials: 'same-origin' });
  if (!res.ok) throw await toAdminError(res);
  return (await res.json()) as T;
}

export async function postAdminJson<T>(
  path: string,
  init: { body?: unknown } = {},
  fetchImpl: typeof fetch = fetch,
): Promise<T> {
  const res = await fetchImpl(path, {
    method: 'POST',
    credentials: 'same-origin',
    ...(init.body !== undefined
      ? { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(init.body) }
      : {}),
  });
  if (!res.ok) throw await toAdminError(res);
  return (await res.json()) as T;
}

export async function patchAdminJson<T>(
  path: string,
  body: unknown,
  fetchImpl: typeof fetch = fetch,
): Promise<T> {
  const res = await fetchImpl(path, {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw await toAdminError(res);
  return (await res.json()) as T;
}

/** DELETE; resolves on 204, throws AdminError (with body, e.g. 409 refs) otherwise. */
export async function deleteAdmin(path: string, fetchImpl: typeof fetch = fetch): Promise<void> {
  const res = await fetchImpl(path, { method: 'DELETE', credentials: 'same-origin' });
  if (!res.ok) throw await toAdminError(res);
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
