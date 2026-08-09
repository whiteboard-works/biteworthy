/**
 * The one place the browser-side contract with an authed proxy route
 * lives: 401 means signed out, a JSON `error` is the message to show, and
 * 204 is success with nothing to parse.
 *
 * Shared rather than copied because it is an auth contract — two copies
 * drift, and the way they drift is one of them stops distinguishing
 * "signed out" from "failed", which sends someone an error toast where a
 * login redirect belongs.
 */
import { NotSignedInError } from './chat';

export async function authedFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { credentials: 'same-origin', ...init });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      // Non-JSON error bodies fall through to the status line.
    }
    throw new Error(message);
  }
  return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
}
