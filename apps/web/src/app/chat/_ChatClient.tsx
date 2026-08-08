'use client';

import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';
import { useRouter } from 'next/navigation';
import {
  NotSignedInError,
  createConversation,
  deleteConversation,
  getConversation,
  listConversations,
  answerConfirmation,
  sendMessage,
  stopTurn,
  watchTurn,
  type Attachment,
  type ChatEvent,
  type ChatMessage,
  type Conversation,
  type ConversationSummary,
  type PageContext,
  type PendingTool,
} from '../../lib/chat';
import { Composer } from './_Composer';
import { Transcript, type LiveTurn } from './_Transcript';

const EMPTY_TURN: LiveTurn = { thinking: '', text: '', tools: [] };

export function ChatClient(): ReactElement {
  const router = useRouter();
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [active, setActive] = useState<Conversation | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pending, setPending] = useState<PendingTool | null>(null);
  const [live, setLive] = useState<LiveTurn | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);

  const onFailure = useCallback(
    (e: unknown) => {
      if (e instanceof NotSignedInError) {
        router.replace(`/login?next=${encodeURIComponent('/chat')}`);
        return;
      }
      setError((e as Error).message);
    },
    [router],
  );

  useEffect(() => {
    listConversations()
      .then((data) => setConversations(data.conversations))
      .catch(onFailure);
  }, [onFailure]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: 'end' });
  }, [messages, live, pending]);

  const adopt = (conversation: Conversation) => {
    setActive(conversation);
    setMessages(conversation.messages);
    setPending(conversation.pending);
  };

  // Refetching after every turn — rather than stitching the streamed
  // fragments into local state — means what's on screen is what the
  // server stored, which is also what a reload would show.
  const refresh = async (id: string) => {
    try {
      const conversation = await getConversation(id);
      adopt(conversation);
      setConversations((current) =>
        current.some((c) => c.id === id)
          ? current.map((c) => (c.id === id ? { ...c, ...conversation } : c))
          : [conversation, ...current],
      );
    } catch (e) {
      onFailure(e);
    }
  };

  const open = async (id: string) => {
    setHistoryOpen(false);
    setError(null);
    setLive(null);
    await refresh(id);
  };

  const startNew = () => {
    setHistoryOpen(false);
    setError(null);
    setLive(null);
    setActive(null);
    setMessages([]);
    setPending(null);
  };

  const remove = async (id: string) => {
    try {
      await deleteConversation(id);
      setConversations((current) => current.filter((c) => c.id !== id));
      if (active?.id === id) startNew();
    } catch (e) {
      onFailure(e);
    }
  };

  const consume = (event: ChatEvent) => {
    if (event.type === 'text_delta') {
      setLive((t) => ({ ...(t ?? EMPTY_TURN), text: (t?.text ?? '') + event.text }));
    } else if (event.type === 'thinking_delta') {
      setLive((t) => ({ ...(t ?? EMPTY_TURN), thinking: (t?.thinking ?? '') + event.text }));
    } else if (event.type === 'tool_use') {
      setLive((t) => ({
        ...(t ?? EMPTY_TURN),
        tools: [...(t?.tools ?? []), { name: event.name }],
      }));
    } else if (event.type === 'tool_result') {
      setLive((t) => {
        const tools = [...(t?.tools ?? [])];
        const last = tools.map((x) => x.name).lastIndexOf(event.name);
        if (last >= 0) tools[last] = { name: event.name, ok: event.ok };
        return { ...(t ?? EMPTY_TURN), tools };
      });
    } else if (event.type === 'error') {
      setError(event.message);
    }
  };

  // Ask, then watch. The turn runs in a job, so the request that starts it
  // returns immediately and the narration is read back separately — which
  // is also why a dropped connection costs nothing but a reconnect.
  const run = async (id: string, ask: () => Promise<{ after: number }>) => {
    setBusy(true);
    setError(null);
    setLive(EMPTY_TURN);
    try {
      const { after } = await ask();
      await watchTurn(id, after, consume);
    } catch (e) {
      onFailure(e);
    } finally {
      setLive(null);
      setBusy(false);
      // The turn was persisted as it ran, so this reconciles whether it
      // finished, parked on a confirmation, or the connection dropped.
      await refresh(id);
    }
  };

  const stop = async () => {
    if (!active) return;
    try {
      await stopTurn(active.id);
    } catch (e) {
      onFailure(e);
    }
  };

  const send = async (text: string, attachments: Attachment[]) => {
    const composed = compose(text, attachments);
    let conversation = active;
    try {
      if (!conversation) {
        conversation = await createConversation();
        adopt(conversation);
      }
    } catch (e) {
      onFailure(e);
      return;
    }

    const id = conversation.id;
    setMessages((current) => [...current, optimistic(composed, current.length)]);
    await run(id, () => sendMessage(id, composed, pageContext()));
  };

  const answer = async (approved: boolean) => {
    if (!active || !pending) return;
    const id = active.id;
    const { fingerprint } = pending;
    setPending(null);
    await run(id, () => answerConfirmation(id, approved, fingerprint));
  };

  return (
    <div className="mx-auto flex h-[calc(100dvh-4rem)] w-full max-w-5xl">
      <History
        conversations={conversations}
        activeId={active?.id ?? null}
        open={historyOpen}
        onOpen={open}
        onNew={startNew}
        onDelete={remove}
      />

      <main className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-zinc-200 px-bw-4 py-bw-3">
          <h1 className="truncate text-bw-lg font-bold text-zinc-900">
            {active?.title ?? 'New chat'}
          </h1>
          <button
            type="button"
            onClick={() => setHistoryOpen((v) => !v)}
            className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 md:hidden"
          >
            History
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-bw-4 py-bw-6">
          {messages.length === 0 && !live ? <Welcome /> : null}
          <Transcript
            messages={messages}
            live={live}
            pending={pending}
            busy={busy}
            onAnswer={(approved) => void answer(approved)}
          />
          {error ? (
            <p role="alert" data-testid="chat-error" className="mt-bw-4 text-bw-sm text-danger">
              {error}
            </p>
          ) : null}
          <div ref={bottom} />
        </div>

        {busy ? (
          <div className="px-bw-4 pb-bw-2">
            <button
              type="button"
              onClick={() => void stop()}
              className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 hover:bg-zinc-50"
            >
              Stop
            </button>
          </div>
        ) : null}
        <Composer disabled={busy || pending !== null} onSend={(t, a) => void send(t, a)} />
      </main>
    </div>
  );
}

function Welcome(): ReactElement {
  return (
    <div className="mb-bw-6 text-bw-base text-zinc-500" data-testid="chat-welcome">
      <p className="font-medium text-zinc-700">Ask about a menu, or add one.</p>
      <ul className="mt-bw-2 list-disc pl-bw-5">
        <li>“What can I eat at Ninis Taqueria?”</li>
        <li>“Add cilantro to my avoid list.”</li>
        <li>Attach a photo of a menu and I&apos;ll read it.</li>
      </ul>
    </div>
  );
}

function History({
  conversations,
  activeId,
  open,
  onOpen,
  onNew,
  onDelete,
}: {
  conversations: ConversationSummary[];
  activeId: string | null;
  open: boolean;
  onOpen: (id: string) => void;
  onNew: () => void;
  onDelete: (id: string) => void;
}): ReactElement {
  return (
    <aside
      data-testid="chat-history"
      className={`${open ? 'block' : 'hidden'} w-full shrink-0 border-r border-zinc-200 md:block md:w-64`}
    >
      <div className="p-bw-3">
        <button
          type="button"
          onClick={onNew}
          className="w-full rounded-bw-md bg-bite px-bw-3 py-bw-2 text-bw-sm font-bold text-white hover:bg-bite-dark"
        >
          New chat
        </button>
      </div>
      <ul className="px-bw-2">
        {conversations.map((conversation) => (
          <li key={conversation.id} className="group flex items-center gap-bw-1">
            <button
              type="button"
              onClick={() => onOpen(conversation.id)}
              className={`flex-1 truncate rounded-bw-md px-bw-2 py-bw-2 text-left text-bw-sm hover:bg-zinc-100 ${
                conversation.id === activeId ? 'bg-zinc-100 font-medium' : 'text-zinc-600'
              }`}
            >
              {conversation.title ?? 'Untitled'}
            </button>
            <button
              type="button"
              aria-label={`Delete ${conversation.title ?? 'conversation'}`}
              onClick={() => onDelete(conversation.id)}
              className="px-bw-1 text-zinc-300 hover:text-danger"
            >
              ×
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}

/**
 * Uploaded files travel as ids, never bytes. Naming them in the message
 * keeps the transcript honest about what was sent, and gives the model
 * the ids `start_menu_scan` needs.
 */
function compose(text: string, attachments: Attachment[]): string {
  if (attachments.length === 0) return text;
  const manifest = attachments
    .map((file) => `[Attached ${file.filename} — attachment_id: ${file.id}]`)
    .join('\n');
  return [text, manifest].filter(Boolean).join('\n\n');
}

/** The chat lives at /chat, so the useful signal is where the user came
 *  from — a restaurant page is the case that matters. */
function pageContext(): PageContext | undefined {
  if (typeof document === 'undefined') return undefined;
  const from = new URL(document.referrer || document.location.href, document.location.href);
  if (from.origin !== document.location.origin) return undefined;
  const restaurant = /^\/restaurants\/([^/]+)/.exec(from.pathname)?.[1];
  return restaurant ? { path: from.pathname, restaurant } : undefined;
}

function optimistic(text: string, index: number): ChatMessage {
  return {
    id: `pending-${index}`,
    role: 'user',
    position: index,
    blocks: [{ type: 'text', text }],
  };
}
