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

/**
 * DELETE that returns a body. The admin delete surface answers 200 with
 * the archived row or `{ id, deleted: true }`, where the taxonomy
 * delete below answers 204 — two shapes, so two helpers rather than one
 * that guesses.
 *
 * `hard` is a separate argument rather than part of the path because it
 * is the difference between hiding a restaurant and destroying it with
 * every menu, item and review attached; a caller has to say it out loud.
 */
export async function deleteAdminJson<T>(
  path: string,
  opts: { hard?: boolean } = {},
  fetchImpl: typeof fetch = fetch,
): Promise<T> {
  const res = await fetchImpl(`${path}${opts.hard ? '?hard=true' : ''}`, {
    method: 'DELETE',
    credentials: 'same-origin',
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

/**
 * Human copy for the delete surface's refusals. Separate from
 * `friendlyAdminError` because a 404 means two different things here:
 * for a read it means admin access is gone, but for `?hard=true` it is
 * how the API declines a non-super admin without confirming the
 * capability exists — and telling someone their access was revoked when
 * they merely lack a tier is a wrong answer that sends them to the
 * wrong place.
 */
export function deleteErrorCopy(err: unknown, opts: { hard?: boolean } = {}): string {
  if (!(err instanceof AdminError)) return friendlyAdminError(err);
  switch (err.code) {
    case 'cannot_delete_self':
      return 'You cannot delete your own account here.';
    case 'cannot_delete_super_admin':
      return 'Super admins are managed on the server — run admin:revoke_super first.';
    case 'soft_delete_unsupported':
      return typeof err.body?.use === 'string'
        ? `That resource does not archive. Use ${err.body.use}.`
        : 'That resource does not archive.';
    case 'in_use':
      return 'Still referenced — remove the references first.';
    default:
      if (opts.hard && err.status === 404) {
        return 'Permanent delete is limited to super admins.';
      }
      return friendlyAdminError(err);
  }
}
