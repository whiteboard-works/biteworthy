/**
 * The chat, for mobile.
 *
 * Mirrors `apps/web/src/lib/chat.ts` in shape, with one deliberate
 * difference: **mobile polls where web streams.** React Native's fetch is
 * XHR-backed and exposes no readable response body, so an SSE connection
 * cannot be consumed without an EventSource polyfill. The narration is
 * rows in `conversation_events` either way — the web relay is just a
 * long-lived reader over the same table — so `fetchEvents` reads them as
 * JSON and the caller decides how often to ask.
 *
 * The cursor is the same one the stream uses, so switching transports
 * loses nothing.
 *
 * Mobile talks to the API directly with the JWT from the keychain; there
 * is no Next proxy here.
 */
import { API_BASE } from '../api-base';

export interface ChatBlockText {
  type: 'text';
  text: string;
}
export interface ChatBlockThinking {
  type: 'thinking';
  text: string;
}
export interface ChatBlockToolUse {
  type: 'tool_use';
  id: string;
  name: string;
  input: Record<string, unknown>;
}
export interface ChatBlockToolResult {
  type: 'tool_result';
  tool_use_id: string;
  ok: boolean;
  text: string | null;
}
export type ChatBlock =
  | ChatBlockText
  | ChatBlockThinking
  | ChatBlockToolUse
  | ChatBlockToolResult;

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  position: number;
  blocks: ChatBlock[];
}

/** The call the confirmation gate parked, and the token that binds an
 *  answer to it. `prompt` is the sentence the tool itself declared. */
export interface PendingTool {
  name: string;
  input: Record<string, unknown>;
  prompt: string | null;
  fingerprint: string | null;
}

/**
 * How much this conversation has agreed to in advance.
 *
 * The gate is the server's — `Chat::ModePolicy` decides what runs, what
 * parks, and what is refused. Nothing here re-implements it.
 */
export type ChatMode = 'planning' | 'manual' | 'accept_edits' | 'auto';

export interface Conversation {
  id: string;
  title: string | null;
  state: 'active' | 'awaiting_confirmation' | 'failed';
  mode: ChatMode;
  pending: PendingTool | null;
  created_at: string;
  updated_at: string;
  messages?: ChatMessage[];
}

/** One line of narration, carrying the cursor to resume from. */
export interface ChatEvent {
  type: string;
  position: number;
  text?: string;
  name?: string;
  ok?: boolean;
  /** The tool's own sentence — "Reading the menu at Nini's". */
  doing?: string | null;
  message?: string;
  tool?: PendingTool;
}

export interface ChatEventsPage {
  events: ChatEvent[];
  /** Whether anything is still in flight. False means stop polling. */
  running: boolean;
}

export interface Attachment {
  id: string;
  filename: string;
  content_type: string;
  byte_size: number;
}

export class ChatError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ChatError';
  }
}

interface Options {
  fetchImpl?: typeof fetch;
}

async function request<T>(
  jwt: string,
  path: string,
  init: RequestInit = {},
  { fetchImpl = fetch }: Options = {},
): Promise<T> {
  const res = await fetchImpl(`${API_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${jwt}`,
      Accept: 'application/json',
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      // Non-JSON error bodies fall through to the status line.
    }
    throw new ChatError(res.status, message);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export function listConversations(
  jwt: string,
  opts: Options = {},
): Promise<{ conversations: Conversation[] }> {
  return request(jwt, '/api/v1/conversations', {}, opts);
}

export function createConversation(jwt: string, opts: Options = {}): Promise<Conversation> {
  return request(jwt, '/api/v1/conversations', { method: 'POST' }, opts);
}

export function getConversation(
  jwt: string,
  id: string,
  opts: Options = {},
): Promise<Conversation> {
  return request(jwt, `/api/v1/conversations/${encodeURIComponent(id)}`, {}, opts);
}

/** Asks for a turn. Returns as soon as the request is recorded — the turn
 *  runs in a job, so this does not wait out a model. */
export function sendMessage(
  jwt: string,
  id: string,
  message: string,
  mode?: ChatMode,
  opts: Options = {},
): Promise<{ queued: boolean; after: number }> {
  return request(
    jwt,
    `/api/v1/conversations/${encodeURIComponent(id)}/messages`,
    { method: 'POST', body: JSON.stringify({ message, mode }) },
    opts,
  );
}

/** Switch modes without sending anything, so the picker survives a
 *  reload. A turn already in flight keeps the mode it was sent under. */
export function setConversationMode(
  jwt: string,
  id: string,
  mode: ChatMode,
  opts: Options = {},
): Promise<Conversation> {
  return request(
    jwt,
    `/api/v1/conversations/${encodeURIComponent(id)}`,
    { method: 'PATCH', body: JSON.stringify({ mode }) },
    opts,
  );
}

/** Answers the confirmation gate. The fingerprint binds the answer to the
 *  call that was drawn, so a stale screen cannot approve a different one. */
export function answerConfirmation(
  jwt: string,
  id: string,
  confirm: boolean,
  fingerprint: string | null,
  mode?: ChatMode,
  opts: Options = {},
): Promise<{ queued: boolean; after: number }> {
  return request(
    jwt,
    `/api/v1/conversations/${encodeURIComponent(id)}/confirm`,
    { method: 'POST', body: JSON.stringify({ confirm, fingerprint, mode }) },
    opts,
  );
}

/** The narration after `after`. Poll this while `running` is true. */
export function fetchEvents(
  jwt: string,
  id: string,
  after: number,
  opts: Options = {},
): Promise<ChatEventsPage> {
  return request(
    jwt,
    `/api/v1/conversations/${encodeURIComponent(id)}/events?after=${after}`,
    {},
    opts,
  );
}

/** Stop. Raises a flag the running turn reads at its next checkpoint. */
export async function stopTurn(
  jwt: string,
  id: string,
  { fetchImpl = fetch }: Options = {},
): Promise<void> {
  const res = await fetchImpl(`${API_BASE}/api/v1/conversations/${encodeURIComponent(id)}/run`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${jwt}` },
  });
  // 409 just means it already finished — not worth surfacing.
  if (!res.ok && res.status !== 409) throw new ChatError(res.status, 'Could not stop that turn.');
}

/** Uploads a menu photo and returns its id. Bytes never reach the agent —
 *  the id does, and `start_menu_scan` resolves it server-side. */
export async function uploadAttachment(
  jwt: string,
  file: { uri: string; name: string; type: string },
  { fetchImpl = fetch }: Options = {},
): Promise<Attachment> {
  const form = new FormData();
  // React Native's FormData takes this shape for a file; it is not a Blob.
  form.append('file', file as unknown as Blob);

  const res = await fetchImpl(`${API_BASE}/api/v1/attachments`, {
    method: 'POST',
    // No Content-Type — the runtime sets the multipart boundary.
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
    body: form,
  });
  if (!res.ok) throw new ChatError(res.status, 'That file could not be uploaded.');
  return (await res.json()) as Attachment;
}

/**
 * Names an attachment in the message text rather than sending it as a side
 * channel — same contract as web. Keeps the transcript honest about what
 * was sent, and gives the model the id `start_menu_scan` needs.
 */
export function compose(text: string, attachments: Attachment[]): string {
  if (attachments.length === 0) return text;
  const manifest = attachments
    .map((file) => `[Attached ${file.filename} — attachment_id: ${file.id}]`)
    .join('\n');
  return [text, manifest].filter(Boolean).join('\n\n');
}
