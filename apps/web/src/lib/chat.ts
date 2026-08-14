/**
 * Client for the first-party chat.
 *
 * Turns stream Server-Sent Events, so `streamTurn` reads the response
 * body rather than awaiting a JSON payload. The stream is a view, not the
 * record: every turn is persisted server-side as it runs, so losing the
 * connection costs nothing — `getConversation` replays it in the same
 * block shapes the events used.
 */

import type {
  ChatMode as ApiChatMode,
  ChatUsage as ApiChatUsage,
  PendingTool as ApiPendingTool,
} from '@biteworthy/api-types';

export type ChatBlock =
  | { type: 'text'; text: string }
  | { type: 'thinking'; text: string }
  | { type: 'tool_use'; id: string; name: string; input: Record<string, unknown> }
  | { type: 'tool_result'; tool_use_id: string; ok: boolean; text: string | null };

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  position: number;
  /** ISO 8601. `position` orders the transcript; this says how long ago. */
  created_at?: string;
  blocks: ChatBlock[];
}

/**
 * The call the confirmation gate parked.
 *
 * `prompt` is the sentence the tool itself declared — what a person
 * approves is never phrased by the model asking for it. `fingerprint`
 * binds an answer to this exact call, so a tab left open on an earlier
 * prompt cannot approve whatever is parked now.
 *
 * Imported from the generated types rather than restated: `codegen:check`
 * fails if this stops matching the rswag spec it came from.
 */
export type PendingTool = ApiPendingTool;

/**
 * How much this conversation has agreed to in advance.
 *
 * The gate is the server's — `Chat::ModePolicy` decides what runs, what
 * parks, and what is refused. Nothing here re-implements that; the picker
 * sends a mode and renders what comes back.
 */
export type ChatMode = ApiChatMode;

export interface ConversationSummary {
  id: string;
  title: string | null;
  state: 'active' | 'awaiting_confirmation' | 'failed';
  mode: ChatMode;
  pending: PendingTool | null;
  created_at: string;
  updated_at: string;
}

/** Spend and cache accounting. Present only for admins — the server
 *  decides, so a non-admin never receives it to begin with.
 *
 *  Generated from the rswag spec, not restated here. */
export type ChatUsage = ApiChatUsage;

export interface Conversation extends ConversationSummary {
  messages: ChatMessage[];
  usage?: ChatUsage;
  /** Whether a tool that writes has run since you last spoke. Sent only
   *  alongside `messages`, so the sidebar's summaries never carry it —
   *  answering it there would mean loading every transcript. */
  can_undo?: boolean;
}

export interface Attachment {
  id: string;
  filename: string;
  content_type: string;
  byte_size: number;
}

/** One `data:` payload from a streaming turn. */
export type ChatEvent =
  | { type: 'open'; conversation_id: string }
  | { type: 'text_delta'; text: string }
  | { type: 'thinking_delta'; text: string }
  | { type: 'tool_use'; name: string; input: Record<string, unknown>; doing?: string | null }
  | { type: 'tool_result'; name: string; ok: boolean }
  | { type: 'done'; text: string | null }
  | { type: 'stopped'; message: string }
  | { type: 'awaiting_confirmation'; tool: PendingTool }
  | { type: 'compacted'; messages: number; tokens_saved: number }
  | { type: 'reconnect'; after: number }
  | { type: 'error'; message: string };

/** Thrown when the session cookie is missing or stale, so callers can
 *  send the user to sign in rather than showing an empty chat. */
export class NotSignedInError extends Error {
  constructor() {
    super('Not signed in');
    this.name = 'NotSignedInError';
  }
}

async function json<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { credentials: 'same-origin', ...init });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) throw new Error(await errorMessage(res));
  return (await res.json()) as T;
}

async function errorMessage(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as { error?: string };
    if (body.error) return body.error;
  } catch {
    // Non-JSON error bodies fall through to the status line.
  }
  return `Request failed (${res.status})`;
}

export function listConversations(): Promise<{ conversations: ConversationSummary[] }> {
  return json('/api/chat/conversations', { cache: 'no-store' });
}

export function createConversation(): Promise<Conversation> {
  return json('/api/chat/conversations', { method: 'POST' });
}

export function getConversation(id: string): Promise<Conversation> {
  return json(`/api/chat/conversations/${encodeURIComponent(id)}`, { cache: 'no-store' });
}

export async function deleteConversation(id: string): Promise<void> {
  const res = await fetch(`/api/chat/conversations/${encodeURIComponent(id)}`, {
    method: 'DELETE',
    credentials: 'same-origin',
  });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) throw new Error(await errorMessage(res));
}

export async function uploadAttachment(file: File): Promise<Attachment> {
  const form = new FormData();
  form.append('file', file);
  // No Content-Type — fetch sets the multipart boundary.
  const res = await fetch('/api/chat/attachments', {
    method: 'POST',
    body: form,
    credentials: 'same-origin',
  });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) throw new Error(await errorMessage(res));
  return (await res.json()) as Attachment;
}

/** What the server accepted, and the narration position to watch from. */
export interface Queued {
  queued: boolean;
  after: number;
}

/** Where the user is standing. Rides with the turn so "what can I eat
 *  here" is answerable without a search first. */
export interface PageContext {
  path?: string;
  restaurant?: string;
}

/** Asks for a turn. Returns as soon as the request is recorded — the turn
 *  itself runs in a job, so this no longer waits out a model. */
export function sendMessage(
  id: string,
  message: string,
  context?: PageContext,
  mode?: ChatMode,
): Promise<Queued> {
  return json(`/api/chat/conversations/${encodeURIComponent(id)}/messages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, context, mode }),
  });
}

export function answerConfirmation(
  id: string,
  confirm: boolean,
  fingerprint: string | null,
  mode?: ChatMode,
): Promise<Queued> {
  return json(`/api/chat/conversations/${encodeURIComponent(id)}/confirm`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ confirm, fingerprint, mode }),
  });
}

/** Switch modes without sending anything, so the picker survives a
 *  reload. A turn already in flight keeps the mode it was sent under. */
export function setConversationMode(id: string, mode: ChatMode): Promise<Conversation> {
  return json(`/api/chat/conversations/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mode }),
  });
}

/** Stop. Raises a flag the running turn reads at its next checkpoint. */
export async function stopTurn(id: string): Promise<void> {
  const res = await fetch(`/api/chat/conversations/${encodeURIComponent(id)}/run`, {
    method: 'DELETE',
    credentials: 'same-origin',
  });
  if (res.status === 401) throw new NotSignedInError();
  // 409 just means it already finished — not worth surfacing.
  if (!res.ok && res.status !== 409) throw new Error(await errorMessage(res));
}

/** Watches a turn's narration from `after` onward.
 *
 *  Because the events are stored rather than only sent, calling this again
 *  with the last position seen resumes where the previous reader stopped —
 *  a dropped connection costs nothing but the reconnect.
 *
 *  Resolves with a position when the server closed the connection while
 *  the turn was still running (a menu scan can outlive one connection),
 *  and with `null` when the turn is genuinely over. The `reconnect` event
 *  is swallowed here rather than passed on: it is transport bookkeeping,
 *  and nothing rendering the transcript should have to know about it. */
export async function watchTurn(
  id: string,
  after: number,
  onEvent: (event: ChatEvent) => void,
  signal?: AbortSignal,
): Promise<number | null> {
  let resume: number | null = null;
  await stream(
    `/api/chat/conversations/${encodeURIComponent(id)}/stream?after=${after}`,
    (event) => {
      if (event.type === 'reconnect') {
        resume = event.after;
        return;
      }
      onEvent(event);
    },
    signal,
  );
  return resume;
}

async function stream(
  path: string,
  onEvent: (event: ChatEvent) => void,
  signal?: AbortSignal,
): Promise<void> {
  const res = await fetch(path, {
    credentials: 'same-origin',
    ...(signal ? { signal } : {}),
  });
  if (res.status === 401) throw new NotSignedInError();
  // Everything the server refuses is refused before the stream opens, so
  // a non-OK status here always carries a readable JSON error.
  if (!res.ok) throw new Error(await errorMessage(res));
  if (!res.body) throw new Error('The connection closed before the reply started.');

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    // Events are separated by a blank line and can be split across any
    // number of chunks, so only whole ones are consumed.
    let boundary = buffer.indexOf('\n\n');
    while (boundary !== -1) {
      const event = parseEvent(buffer.slice(0, boundary));
      buffer = buffer.slice(boundary + 2);
      if (event) onEvent(event);
      boundary = buffer.indexOf('\n\n');
    }
  }
}

function parseEvent(raw: string): ChatEvent | null {
  const data = raw
    .split('\n')
    .filter((line) => line.startsWith('data:'))
    .map((line) => line.slice(5).trim())
    .join('');
  if (!data) return null;
  try {
    return JSON.parse(data) as ChatEvent;
  } catch {
    return null;
  }
}
