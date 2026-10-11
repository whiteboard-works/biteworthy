/**
 * The private "notes for the assistant" on the caller's profile. Mirrors
 * the web settings section against GET/PATCH /api/v1/profile.
 *
 * The PATCH sends `chat_notes` alone: that endpoint replaces any array
 * it receives wholesale, so a payload carrying avoid lists rebuilt from
 * an earlier read could drop an allergen another client just added.
 */
import { API_BASE } from '../api-base';

/** Mirrors `UserProfile::CHAT_NOTES_MAX_LENGTH` in the API. */
export const CHAT_NOTES_MAX_LENGTH = 500;

export class ProfileError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ProfileError';
  }
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export async function fetchChatNotes(jwt: string, opts: FetchOptions = {}): Promise<string | null> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/profile`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw new ProfileError(res.status, `fetchChatNotes failed: ${res.status}`);
  const body = (await res.json()) as { chat_notes: string | null };
  return body.chat_notes;
}

/** Saves the notes (the server trims; blank clears) and returns what it stored. */
export async function saveChatNotes(
  notes: string,
  jwt: string,
  opts: FetchOptions = {},
): Promise<string | null> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/profile`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ chat_notes: notes }),
  });
  if (!res.ok) {
    let message = `saveChatNotes failed: ${res.status}`;
    if (res.status === 422) {
      try {
        const body = (await res.json()) as { errors?: Record<string, string[]> };
        const first = body.errors?.chat_notes?.[0];
        if (first) message = `Notes ${first}`;
      } catch {
        // non-JSON body — keep the status message
      }
    }
    throw new ProfileError(res.status, message);
  }
  const body = (await res.json()) as { chat_notes: string | null };
  return body.chat_notes;
}
