'use client';

import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';
import { useRouter } from 'next/navigation';
import { useTracker } from '../_PostHogProvider';
import {
  NotSignedInError,
  createConversation,
  deleteConversation,
  getConversation,
  listConversations,
  answerConfirmation,
  sendMessage,
  setConversationMode,
  stopTurn,
  watchTurn,
  type Attachment,
  type ChatEvent,
  type ChatMode,
  type ChatUsage,
  type ChatMessage,
  type Conversation,
  type ConversationSummary,
  type PageContext,
  type PendingTool,
} from '../../lib/chat';
import { Composer, type QueuedMessage } from './_Composer';
import { ModeNotice, ModePicker } from './_ModePicker';
import { Transcript, type LiveTurn } from './_Transcript';
import { useToolVisibility } from './_useToolVisibility';

const EMPTY_TURN: LiveTurn = { thinking: '', text: '', tools: [] };

/** Enough hops for a very long scan; a bound, not an expectation. */
const MAX_RECONNECTS = 20;

export function ChatClient(): ReactElement {
  const router = useRouter();
  const tracker = useTracker();
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [active, setActive] = useState<Conversation | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pending, setPending] = useState<PendingTool | null>(null);
  const [live, setLive] = useState<LiveTurn | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [showTools, toggleTools] = useToolVisibility();
  const [mode, setMode] = useState<ChatMode>('manual');
  const [queued, setQueued] = useState<QueuedMessage[]>([]);
  const bottom = useRef<HTMLDivElement>(null);
  // The queue is read from inside `run`'s teardown, which closes over the
  // render that started the turn — by then `queued` is whatever it was a
  // minute ago. The ref is the current one; the state is what draws.
  const queue = useRef<QueuedMessage[]>([]);
  // `deliver` closes over `active` and `mode`, and the flush happens a
  // turn later, so the same staleness applies to it.
  const deliverLatest = useRef<
    (text: string, attachments: Attachment[], known?: Conversation) => Promise<boolean>
  >(async () => false);
  // A send is under way but `busy` has not caught up yet — see `deliver`.
  const inFlight = useRef(false);
  // A mode switch is in the air. `adopt` must not overwrite the picker
  // with the value the server had before the PATCH landed.
  const switchingMode = useRef(false);
  // Which switch is the newest, so an older PATCH resolving late cannot
  // speak for the picker.
  const modeTicket = useRef(0);
  // Which conversation is on screen *now*. `run`'s teardown closes over
  // the render that started the turn, and the history controls let
  // someone open another conversation while one is still running — so
  // the fallback below has to ask this rather than trust `active`.
  const shown = useRef<string | null>(null);

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
    shown.current = conversation.id;
    setActive(conversation);
    setMessages(conversation.messages);
    setPending(conversation.pending);
    // Absent reads as `manual`, matching `ModePolicy.resolve` — an older
    // API that does not send one must not leave the picker claiming a
    // looser gate than the server is applying.
    //
    // Skipped while a switch is in the air: a turn's teardown refresh can
    // be served before the PATCH commits, and adopting that response
    // would snap the picker back to the mode the user just left — then
    // stamp it onto the next send, re-enabling writes they had turned
    // off. Which is the exact direction this must never fail in.
    if (!switchingMode.current) setMode(conversation.mode ?? 'manual');
  };

  // Emptying it here rather than at every call site: a queued message
  // belongs to the conversation it was typed into, and there is no
  // reading of "send it to the other one" that a user would want.
  const clearQueue = () => {
    queue.current = [];
    setQueued([]);
  };

  // Refetching after every turn — rather than stitching the streamed
  // fragments into local state — means what's on screen is what the
  // server stored, which is also what a reload would show.
  const refresh = async (id: string): Promise<Conversation | null> => {
    try {
      const conversation = await getConversation(id);
      adopt(conversation);
      setConversations((current) =>
        current.some((c) => c.id === id)
          ? current.map((c) => (c.id === id ? { ...c, ...conversation } : c))
          : [conversation, ...current],
      );
      return conversation;
    } catch (e) {
      onFailure(e);
      return null;
    }
  };

  const open = async (id: string) => {
    setHistoryOpen(false);
    setError(null);
    shown.current = id;
    setLive(null);
    clearQueue();
    await refresh(id);
  };

  const startNew = () => {
    setHistoryOpen(false);
    setError(null);
    shown.current = null;
    setLive(null);
    setActive(null);
    setMessages([]);
    setPending(null);
    clearQueue();
    // A fresh conversation starts where the server starts it. Carrying
    // the last one's mode over means someone who used `auto` once gets a
    // new chat silently in `auto` — a gate turned off by a decision they
    // made about a different conversation.
    setMode('manual');
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
        tools: [...(t?.tools ?? []), { name: event.name, doing: event.doing ?? null }],
      }));
    } else if (event.type === 'tool_result') {
      setLive((t) => {
        const tools = [...(t?.tools ?? [])];
        const last = tools.map((x) => x.name).lastIndexOf(event.name);
        if (last >= 0) tools[last] = { ...tools[last], name: event.name, ok: event.ok };
        return { ...(t ?? EMPTY_TURN), tools };
      });
    } else if (event.type === 'error') {
      setError(event.message);
    }
  };

  // Ask, then watch. The turn runs in a job, so the request that starts it
  // returns immediately and the narration is read back separately — which
  // is also why a dropped connection costs nothing but a reconnect.
  // Answers whether the server *accepted* the turn, which is a different
  // question from whether it went well. Once `ask` resolves the message is
  // recorded server-side and watching it is bookkeeping — a connection
  // that drops mid-narration must not read as "nothing was sent", or the
  // caller puts a message back that is already on its way.
  const run = async (id: string, ask: () => Promise<{ after: number }>): Promise<boolean> => {
    setBusy(true);
    setError(null);
    setLive(EMPTY_TURN);
    const startedAt = Date.now();
    let tools = 0;
    let outcome = 'error';
    let accepted = false;
    // The answer as the server settled on it, which is not always what
    // streamed — a flagged turn's repair replaces the text after the
    // fact, and the disclaimer arrives after that. Kept so the refetch
    // below has something honest to fall back to when it fails.
    let settledText: string | null = null;
    try {
      const { after } = await ask();
      accepted = true;
      // A turn can outlive one connection — a menu scan legitimately runs
      // past the server's window. Each hop resumes from the position the
      // server handed back, so the narration is continuous on screen and
      // the reconnect is invisible. Capped so a server stuck asking for
      // reconnects cannot spin the client forever.
      let cursor = after;
      for (let hop = 0; hop < MAX_RECONNECTS; hop += 1) {
        const resume = await watchTurn(id, cursor, (event) => {
          if (event.type === 'tool_use') tools += 1;
          if (event.type === 'done') {
            outcome = 'done';
            settledText = event.text;
          }
          if (event.type === 'awaiting_confirmation') outcome = 'awaiting_confirmation';
          consume(event);
        });
        if (resume === null) break;
        cursor = resume;
      }
    } catch (e) {
      onFailure(e);
    } finally {
      // Counts and outcome only — never the message, never which tools.
      // A tool name on an identified event would say this account edited
      // a dietary profile, which is the health-adjacency the taxonomy
      // already strips from profile_set.
      tracker.track('chat_turn_completed', {
        outcome,
        tool_count: tools,
        duration_ms: Date.now() - startedAt,
      });
      setLive(null);
      setBusy(false);
      // The turn was persisted as it ran, so this reconciles whether it
      // finished, parked on a confirmation, or the connection dropped.
      const conversation = await refresh(id);
      // And if that reconciliation is the thing that failed, put the
      // answer back. Clearing the live turn before refetching is right on
      // the happy path — it is what stops the streamed copy and the
      // stored one both being on screen — but it means one failed GET
      // erases a turn the server has already written down and the user
      // has already read. `done` carries the settled text precisely so
      // this does not need the network twice.
      // Written into `messages` rather than the single `live` slot, for
      // two reasons the slot cannot cover. It is global, so a turn in
      // conversation A whose refetch fails would draw A's answer under
      // B's transcript if the reader had moved on — dietary text
      // attributed to the wrong question. And it is transient: the queue
      // flush below starts the next turn, which opens with
      // `setLive(EMPTY_TURN)` and would erase this before it was read.
      // The next successful `adopt` replaces `messages` wholesale, so
      // the stand-in cannot linger or accumulate.
      const restored = settledText;
      if (!conversation && restored && shown.current === id) {
        setMessages((current) => [
          ...current,
          {
            id: `local-${current.length}`,
            role: 'assistant',
            position: current.length,
            created_at: new Date().toISOString(),
            blocks: [{ type: 'text', text: restored }],
          },
        ]);
      }
      // Flushed here rather than from an effect on `busy`. An effect
      // would fire on the render where `busy` flips false and the queue
      // has already been shortened, which is one render before the next
      // turn sets it back — two queued messages would leave together and
      // race two readers onto one stream. Draining from the teardown of
      // the turn that was blocking them is the one moment that cannot
      // overlap with itself.
      //
      // Not while a confirmation is parked: the server refuses a message
      // behind one, and more to the point the queued message may well be
      // the user changing their mind about the thing being asked.
      //
      // `?? active` covers a failed refresh. Without it a `getConversation`
      // error strands the whole queue: the turn is over, `busy` is false,
      // and nothing else drains it — the chips would sit there forever
      // behind a generic error.
      const settled = conversation ?? active;
      // Only when the server took this turn. If `ask` was rejected, the
      // message it was carrying is on its way back to the head of the
      // queue — flushing now would send the one behind it first and
      // deliver the two out of the order they were typed.
      if (accepted && settled && !settled.pending) flush(settled);
    }
    return accepted;
  };

  // The conversation is handed in rather than read from state: the
  // `setActive` that just ran may not have re-rendered yet, and a
  // `deliver` that reads `active` as null opens a second conversation
  // and sends the queued message into it.
  const flush = (conversation: Conversation) => {
    // Only this conversation's messages. `busy` is global, so a turn
    // running in A while the user opens B and types puts B's message in
    // the same queue — and A's teardown would then deliver it into A.
    // `null` is a message typed during the very first send, before the
    // conversation existed — this is the one it was meant for.
    const next = queue.current.find(
      (message) => message.conversationId === conversation.id || message.conversationId === null,
    );
    if (!next) return;

    queue.current = queue.current.filter((message) => message.id !== next.id);
    setQueued(queue.current);
    void deliverLatest.current(next.text, next.attachments, conversation).then((sent) => {
      if (sent) return;
      // Put it back where it was rather than losing it. Removing it first
      // is what keeps a second flush from picking up the same message,
      // but it means a send that never reached the server would otherwise
      // vanish with nothing but an error banner to show for it.
      queue.current = [next, ...queue.current];
      setQueued(queue.current);
    });
  };

  const stop = async () => {
    if (!active) return;
    try {
      await stopTurn(active.id);
    } catch (e) {
      onFailure(e);
    }
  };

  // Resolves false when the message never reached the server, so the
  // caller can put it back where it came from.
  const deliver = async (
    text: string,
    attachments: Attachment[],
    known?: Conversation,
  ): Promise<boolean> => {
    const composed = compose(text, attachments);
    let conversation = known ?? active;
    // `busy` is React state set inside `run`, which on a first message
    // only runs after `createConversation` resolves — two sends inside
    // that window would both see an idle chat and open two conversations.
    // A ref latches synchronously, which is the whole point.
    inFlight.current = true;
    try {
      if (!conversation) {
        conversation = await createConversation();
        adopt(conversation);
        tracker.track('chat_started', { surface: 'web' });
      }
    } catch (e) {
      onFailure(e);
      inFlight.current = false;
      return false;
    }

    const id = conversation.id;
    setMessages((current) => [...current, optimistic(composed, current.length)]);
    try {
      return await run(id, () => sendMessage(id, composed, pageContext(), mode));
    } finally {
      inFlight.current = false;
    }
  };
  deliverLatest.current = deliver;

  // What the composer calls. Either this goes now or it waits its turn —
  // the composer does not need to know which, and the user finds out by
  // seeing a chip appear instead of a message.
  const send = (text: string, attachments: Attachment[]) => {
    // The id is a React key and a cancel handle, nothing more: it only
    // has to be unique among the handful queued at once. The length
    // suffix is there because two messages sent inside the same
    // millisecond would otherwise collide.
    const message: QueuedMessage = {
      id: `queued-${Date.now()}-${queue.current.length}`,
      conversationId: active?.id ?? null,
      text,
      attachments,
    };

    const idle = !busy && !inFlight.current && pending === null;
    // `queue.current.length` is part of "idle" on purpose. Without it a
    // message typed while a backlog is waiting jumps the queue and
    // arrives before messages typed earlier — reachable whenever a flush
    // was interrupted and left chips behind.
    if (idle && queue.current.length === 0) {
      void deliver(text, attachments).then((sent) => {
        if (sent) return;
        // The composer has already cleared itself, so a rejected POST
        // would otherwise take the message with it. It becomes a chip
        // instead — visible, cancelable, and picked up by the next
        // flush, which beats restoring text into a box the user has
        // probably started typing in again.
        queue.current = [message, ...queue.current];
        setQueued(queue.current);
      });
      return;
    }

    queue.current = [...queue.current, message];
    setQueued(queue.current);

    // Queued while nothing is running means an earlier flush was
    // interrupted. Draining now — after appending, so order holds — is
    // what gets the backlog moving again without asking the user to
    // understand any of this.
    if (idle && active) flush(active);
  };

  const cancelQueued = (id: string) => {
    queue.current = queue.current.filter((message) => message.id !== id);
    setQueued(queue.current);
  };

  const answer = async (approved: boolean) => {
    if (!active || !pending) return;
    const id = active.id;
    const { fingerprint } = pending;
    setPending(null);
    tracker.track('chat_confirmed', { approved });
    await run(id, () => answerConfirmation(id, approved, fingerprint, mode));
  };

  // Persisted so the picker survives a reload; a conversation that does
  // not exist yet has nowhere to persist it, and the first `sendMessage`
  // carries it instead.
  const changeMode = (next: ChatMode) => {
    const previous = mode;
    setMode(next);
    if (!active) return;

    // Switch twice quickly and two PATCHes are in the air with no
    // ordering between them; the older one landing last would leave the
    // picker and the server disagreeing about which gate is on. The
    // counter makes every response except the newest a no-op.
    const ticket = (modeTicket.current += 1);
    switchingMode.current = true;
    setConversationMode(active.id, next)
      .catch((e) => {
        if (ticket !== modeTicket.current) return;
        setMode(previous);
        onFailure(e);
      })
      .finally(() => {
        if (ticket === modeTicket.current) switchingMode.current = false;
      });
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
          <div className="flex items-center gap-bw-2">
            <ModePicker mode={mode} onChange={changeMode} />
            {/* A per-person preference for a quieter read, not a new
                default — showing every tool call is the honest-disclosure
                claim made visible, so it stays on unless someone turns it
                off.

                A state label, not an action one. "Hide tools" alongside
                `aria-pressed={showTools}` announces as "Hide tools,
                pressed" in exactly the state where tools are still
                showing, which reads as the opposite of the truth. The
                canonical toggle is a stable name plus a pressed state,
                and the fill carries the same signal visually. */}
            <button
              type="button"
              onClick={toggleTools}
              aria-pressed={showTools}
              data-testid="tools-toggle"
              className={`rounded-bw-md border px-bw-3 py-bw-1 text-bw-sm ${
                showTools
                  ? 'border-zinc-400 bg-zinc-100 text-zinc-900'
                  : 'border-zinc-300 text-zinc-500'
              }`}
            >
              Tools
            </button>
            <button
              type="button"
              onClick={() => setHistoryOpen((v) => !v)}
              className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 md:hidden"
            >
              History
            </button>
          </div>
        </header>

        <ModeNotice mode={mode} />

        <div className="flex-1 overflow-y-auto px-bw-4 py-bw-6">
          {messages.length === 0 && !live ? <Welcome /> : null}
          <Transcript
            messages={messages}
            live={live}
            pending={pending}
            busy={busy}
            showTools={showTools}
            onAnswer={(approved) => void answer(approved)}
          />
          {active?.usage ? <UsagePills usage={active.usage} /> : null}
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
        {/* Only once the turn is over: mid-turn the honest control is
            Stop, and showing both invites undoing work still running.
            Whether there is anything to reverse is the server's call —
            it reads the tool annotations, the client only renders. */}
        {!busy && active?.can_undo ? (
          <div className="px-bw-4 pb-bw-2">
            <button
              type="button"
              data-testid="undo-turn"
              onClick={() => send('Undo everything you just did.', [])}
              className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 hover:bg-zinc-50"
            >
              Undo that
            </button>
          </div>
        ) : null}
        <Composer
          queueing={busy || pending !== null}
          queued={queued}
          onSend={send}
          onCancelQueued={cancelQueued}
        />
      </main>
    </div>
  );
}

/**
 * What the last turn cost. Rendered only when the server sent it, which
 * it does only for admins — the visibility decision lives server-side, so
 * there is nothing here to get wrong.
 */
/**
 * Outcomes worth a pill. `done` is the happy path and `nothing_queued` is
 * a job finding its work already drained — neither tells the operator
 * anything, and printing them crowds out the one that would.
 */
const BENIGN_OUTCOMES = new Set(['done', 'nothing_queued']);

function interesting(outcome: string | null | undefined): string | null {
  return outcome && !BENIGN_OUTCOMES.has(outcome) ? outcome : null;
}

function formatCost(cents: number): string {
  if (cents < 100) return `${cents}¢`;
  return `$${(cents / 100).toFixed(2)}`;
}

function UsagePills({ usage }: { usage: ChatUsage }): ReactElement {
  const run = usage.last_run;
  const pills = [
    // Two scopes, said out loud. The old footer showed only the
    // conversation lifetime and labelled it "total" beside per-run token
    // counts, which invited reading a whole conversation's spend as the
    // price of the last dozen tokens.
    run ? `${formatCost(run.cost_cents)} turn` : null,
    `${formatCost(usage.cost_cents)} conversation`,
    run ? `${run.rounds} rounds` : null,
    run
      ? `${run.cache_read_tokens.toLocaleString()} cache r / ${run.cache_write_tokens.toLocaleString()} w`
      : null,
    run
      ? `${run.input_tokens.toLocaleString()} in / ${run.output_tokens.toLocaleString()} out`
      : null,
    run?.duration_ms ? `${(run.duration_ms / 1000).toFixed(1)}s` : null,
    // Two outcomes, because there are two runs. How the run these numbers
    // came from ended, and — only when it is something else worth seeing
    // — how the newest run ended.
    //
    // Showing only the newest one hides real failures behind harmless
    // ones: send two messages quickly, one job drains both, the second
    // turn ends `timed_out` with eight rounds, then a second job finds
    // nothing queued and releases `nothing_queued`. The footer would
    // report the timed-out run's numbers under a `nothing_queued` label
    // and the failure would be gone.
    interesting(run?.outcome),
    usage.last_outcome?.outcome !== run?.outcome ? interesting(usage.last_outcome?.outcome) : null,
  ].filter((p): p is string => p !== null);

  return (
    <div data-testid="usage-pills" className="mt-bw-4 flex flex-wrap gap-bw-1">
      {pills.map((pill) => (
        <span
          key={pill}
          className="rounded-bw-md bg-zinc-100 px-bw-2 py-bw-1 text-bw-xs text-zinc-500"
        >
          {pill}
        </span>
      ))}
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
