'use client';

import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';
import { useRouter } from 'next/navigation';
import { useTracker } from '../_PostHogProvider';
import { DisclaimerNote } from '../_SiteDisclaimer';
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
  type ChatPane,
  type ChatUsage,
  type ChatMessage,
  type Conversation,
  type ConversationSummary,
  type PageContext,
  type DeviceLocation,
  type PendingTool,
} from '../../lib/chat';
import { Composer, type QueuedMessage } from './_Composer';
import { useDeviceLocation } from './_useDeviceLocation';
import { ModeNotice, ModePicker } from './_ModePicker';
import { ResultsPane } from './_ResultsPane';
import { Transcript, type LiveTurn } from './_Transcript';

const EMPTY_TURN: LiveTurn = { thinking: '', text: '', tools: [], notices: [] };

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
  const deviceLocation = useDeviceLocation();
  const [mode, setMode] = useState<ChatMode>('manual');
  const [queued, setQueued] = useState<QueuedMessage[]>([]);
  // What the results pane is pointed at — the last thing a tool acted on
  // in the chat on screen. Set by the live `pane` event and by the stored
  // copy on every adopt, so a reopened chat shows what it was looking at.
  const [pane, setPane] = useState<ChatPane | null>(null);
  // Counts live `pane` events, so a tool that acts on the same thing the
  // pane already shows — an accept on the scan it is listing — still
  // makes it look again. Adopting a stored pane does not count: it is
  // the same reference the live event already drew.
  const [paneRevision, setPaneRevision] = useState(0);
  // Phone width: the pane takes the transcript's place while open.
  const [paneOpen, setPaneOpen] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);
  // The queue is read from inside `run`'s teardown, which closes over the
  // render that started the turn — by then `queued` is whatever it was a
  // minute ago. The ref is the current one; the state is what draws.
  const queue = useRef<QueuedMessage[]>([]);
  // `deliver` closes over `active` and `mode`, and the flush happens a
  // turn later, so the same staleness applies to it.
  const deliverLatest = useRef<
    (
      text: string,
      attachments: Attachment[],
      known?: Conversation,
      bind?: (id: string) => void,
    ) => Promise<boolean>
  >(async () => false);
  // The one turn this tab is running, and the chat it belongs to — `id`
  // is null only while `deliver` is still creating that chat. It is set
  // synchronously, before `busy` can catch up, which is what stops two
  // quick sends from both seeing an idle chat. Compared by identity: only
  // the turn that claimed it, or the deletion of its chat, may let it go.
  const turn = useRef<{ id: string | null } | null>(null);
  // The chat on screen, or the one being opened. Set before the request
  // that fetches it, so an answer for any other chat — a finished turn's
  // refresh, a late event — knows it no longer owns the screen.
  const viewing = useRef<string | null>(null);
  // `active` as of the latest adopt, for teardowns that closed over an
  // older render.
  const current = useRef<Conversation | null>(null);
  // A mode switch is in the air. `adopt` must not overwrite the picker
  // with the value the server had before the PATCH landed.
  const switchingMode = useRef(false);
  // Which switch is the newest, so an older PATCH resolving late cannot
  // speak for the picker.
  const modeTicket = useRef(0);
  // Deletes started from this tab, each resolving to whether it worked.
  // Deleting a chat mid-turn takes its run with it, so the turn's watcher
  // and teardown refresh both fail — news to no one, and not worth an
  // error on the blank chat that replaced it. A turn waits on the answer
  // rather than the attempt: if the delete fails, the chat is still there
  // and its teardown has to run as usual.
  const deletions = useRef(new Map<string, Promise<boolean>>());
  // Chats that no longer exist — deleted, or blank chats abandoned before
  // they could be created — for the checks that cannot wait on a promise.
  const removed = useRef(new Set<string>());
  // Which blank chat is on screen (see `blankKey`), and which blank chats
  // have a create in flight.
  const blank = useRef(0);
  const creating = useRef(new Set<string>());

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
    viewing.current = conversation.id;
    current.current = conversation;
    setActive(conversation);
    setMessages(conversation.messages);
    setPending(conversation.pending);
    // Only when the server spoke to it. The web deploys ahead of the API,
    // and in that window a refetch that carries no `pane` field must not
    // blank what the live event just drew; an explicit null still clears.
    if (conversation.pane !== undefined) setPane(conversation.pane);
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

  // A queued message belongs to the conversation it was typed into, and
  // there is no reading of "send it to the other one" that a user would
  // want — so each carries its chat's id and waits for that chat, however
  // often the person switches away and back.
  //
  // A blank chat has no id yet, so each one gets a key of its own rather
  // than sharing null: two blank chats in a row — "New chat" pressed while
  // the first was still being created — are two different conversations,
  // and their messages must not trade places.
  const blankKey = () => `blank:${blank.current}`;
  // Leaving a blank chat for a new one drops what was typed into it —
  // unless it is still being created, in which case its messages are
  // about to be re-tagged with the real id and wait for it.
  const leaveBlank = () => {
    const key = blankKey();
    blank.current += 1;
    if (creating.current.has(key)) return;
    queue.current = queue.current.filter((message) => message.conversationId !== key);
    setQueued(queue.current);
  };

  // Back to the head of the queue after a send that never reached the
  // server — unless its chat was deleted in the meantime. A chip for a
  // chat that no longer exists could never drain, and while it sat there
  // every later message would queue behind it.
  const putBack = (message: QueuedMessage) => {
    if (message.conversationId && removed.current.has(message.conversationId)) return;
    queue.current = [message, ...queue.current];
    setQueued(queue.current);
  };

  // Refetching after every turn — rather than stitching the streamed
  // fragments into local state — means what's on screen is what the
  // server stored, which is also what a reload would show.
  //
  // Checked after the request, not before: the person can delete this
  // chat or move to another while it is in flight, and a late answer —
  // the chat or its 404 — must neither bring back what they deleted nor
  // pull them away from what they opened. Returns null when the answer
  // no longer belongs on screen.
  const refresh = async (id: string): Promise<Conversation | null> => {
    const deletedMeanwhile = async () => (await deletions.current.get(id)) ?? false;
    try {
      const conversation = await getConversation(id);
      if (await deletedMeanwhile()) return null;
      setConversations((list) =>
        list.some((c) => c.id === id)
          ? list.map((c) => (c.id === id ? { ...c, ...conversation } : c))
          : [conversation, ...list],
      );
      if (viewing.current !== id) return null;
      adopt(conversation);
      return conversation;
    } catch (e) {
      if (!(await deletedMeanwhile()) && viewing.current === id) onFailure(e);
      return null;
    }
  };

  const open = async (id: string) => {
    const fromBlank = viewing.current === null;
    viewing.current = id;
    setHistoryOpen(false);
    // Whatever they had open on a phone, the chat they picked is what
    // they asked to see.
    setPaneOpen(false);
    // A chat opened is a chat looked at afresh: even a pane pointing at
    // the same menu as the last one is fetched again, under whatever the
    // filter is now — not what it was when another chat drew it.
    setPaneRevision((n) => n + 1);
    setError(null);
    setLive(null);
    const opened = await refresh(id);
    // A failed open leaves the previous chat drawn; point the page back
    // at it, or that chat would read as off screen and stop updating.
    // Leaving a blank chat for an existing one retires it just as "New
    // chat" does — nothing can navigate back to a chat with no id. Only
    // once the open worked: a failed one puts the blank chat back on
    // screen, and what was queued in it has to still be there.
    if (opened && fromBlank) leaveBlank();
    if (!opened && viewing.current === id) {
      viewing.current = current.current?.id ?? null;
      // That chat is on screen again, so its queue is drainable again.
      if (turn.current === null) flushView();
    }
    // Whatever was left waiting here — typed before the person switched
    // away, or a send that failed while they were elsewhere — goes now,
    // unless another turn still holds the page (its teardown drains the
    // queue for whatever is on screen) or a confirmation is parked.
    if (opened && turn.current === null && !opened.pending) flush(opened);
  };

  const startNew = () => {
    viewing.current = null;
    current.current = null;
    setHistoryOpen(false);
    setError(null);
    setLive(null);
    setActive(null);
    setMessages([]);
    setPending(null);
    setPane(null);
    setPaneOpen(false);
    leaveBlank();
    // A fresh conversation starts where the server starts it. Carrying
    // the last one's mode over means someone who used `auto` once gets a
    // new chat silently in `auto` — a gate turned off by a decision they
    // made about a different conversation.
    setMode('manual');
  };

  const remove = async (id: string) => {
    const attempt = deleteConversation(id).then(
      () => true,
      (e: unknown) => {
        onFailure(e);
        return false;
      },
    );
    deletions.current.set(id, attempt);
    if (await attempt) {
      removed.current.add(id);
      setConversations((list) => list.filter((c) => c.id !== id));
      // Its queued messages go with it, whether or not it is on screen.
      queue.current = queue.current.filter((message) => message.conversationId !== id);
      setQueued(queue.current);
      if (viewing.current === id) {
        startNew();
      } else if (current.current?.id === id) {
        // Still drawn while another chat is being opened: clear it without
        // cancelling that open.
        current.current = null;
        setActive(null);
        setMessages([]);
        setPending(null);
        setPane(null);
        setPaneOpen(false);
      }
      // Only a turn this chat owns is released, and it is released now
      // rather than when its dead stream gets round to closing: until then
      // whatever is on screen would queue behind a turn that no longer
      // exists. That turn's teardown leaves the page alone from here on.
      if (turn.current?.id === id) {
        turn.current = null;
        setBusy(false);
        flushView();
      }
    } else {
      deletions.current.delete(id);
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
    } else if (event.type === 'compacted') {
      // Said plainly, on the turn it happens. The alternative is an
      // assistant that appears to forget a menu it had already read, with
      // nothing on screen connecting the two.
      setLive((t) => ({
        ...(t ?? EMPTY_TURN),
        notices: [
          ...(t?.notices ?? []),
          `Trimmed ${event.messages} earlier tool ${
            event.messages === 1 ? 'result' : 'results'
          } to keep this conversation within its budget. I can fetch anything I still need.`,
        ],
      }));
    } else if (event.type === 'pane') {
      // Only ever for the chat on screen — `run` drops every event for
      // any other, and the stored copy catches that chat up on open.
      setPane(event.pane);
      setPaneRevision((n) => n + 1);
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
    // `deliver` claimed the turn before the chat existed; a confirmation
    // answer arrives here without one.
    const mine = turn.current?.id === id ? turn.current : { id };
    turn.current = mine;
    const onScreen = () => viewing.current === id;
    setBusy(true);
    setError(null);
    // Only on its own chat: teardown clears it only there, so a turn that
    // starts off screen would leave another chat "thinking" for good.
    if (onScreen()) setLive(EMPTY_TURN);
    const startedAt = Date.now();
    let tools = 0;
    let outcome = 'error';
    let accepted = false;
    let failure: unknown = null;
    let gone = false;
    // Whether a `pane` event followed the latest tool call — see the
    // refetch below. Per tool, not per turn: a menu read early in the
    // turn shows one, and a filter change after it may lose its own.
    let sawPane = false;
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
          if (event.type === 'tool_use') {
            tools += 1;
            sawPane = false;
          }
          if (event.type === 'pane') sawPane = true;
          if (event.type === 'done') outcome = 'done';
          if (event.type === 'awaiting_confirmation') outcome = 'awaiting_confirmation';
          // Narration belongs to its own chat. Once that chat is off
          // screen or being deleted, nothing this turn says belongs on the
          // page — not its text, and not the error event the server sends
          // when a deleted run vanishes. A failed delete shows its own.
          if (!onScreen() || deletions.current.has(id)) return;
          consume(event);
        });
        if (resume === null) break;
        cursor = resume;
      }
    } catch (e) {
      failure = e;
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
      // A delete in flight speaks for this turn: if it worked there is
      // nothing to report and `remove` has already handed the page back,
      // and if it failed its own error is the one that matters — the chat
      // the person tried to remove is still there.
      const deleting = deletions.current.get(id);
      gone = (await deleting) ?? false;
      // The claim — and `busy` with it — is held through the refresh and
      // the flush: a send slipped into that gap would start a turn the
      // refresh then overwrites with the snapshot from before it, and a
      // confirmation answered there would have nowhere to go.
      if (onScreen()) setLive(null);
      if (failure && !deleting && onScreen()) onFailure(failure);
      // The turn was persisted as it ran, so this reconciles whether it
      // finished, parked on a confirmation, or the connection dropped.
      // `refresh` only redraws if this chat is still the one on screen.
      const conversation = gone ? null : await refresh(id);
      // The stream can drop after a write and before its `pane` event —
      // past the reconnect cap, or with the run gone. The refetch then
      // hands back the stored pane, which after `set_strictness` is the
      // same reference the pane already shows, and the same reference
      // would not be looked at again — leaving "you can eat" labels from
      // before the change. A turn whose latest tool call was not followed
      // by a pane event makes the pane look again anyway.
      if (conversation?.pane && tools > 0 && !sawPane && onScreen()) {
        setPaneRevision((n) => n + 1);
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
      // `?? current` covers a failed refresh. Without it a
      // `getConversation` error strands the whole queue: the turn is over,
      // `busy` is false, and nothing else drains it — the chips would sit
      // there forever behind a generic error.
      //
      // Only the turn that still holds the page drains it — asked again
      // after the refresh, which a delete may have landed during — and it
      // drains whatever is on screen: a person who moved to another chat
      // mid-turn queued their messages there.
      //
      // Released after, and only if nothing claimed it meanwhile: the
      // flush's own `deliver` claims it synchronously for the next turn.
      if (turn.current === mine) {
        turn.current = null;
        setBusy(false);
        if (onScreen()) {
          const settled = conversation ?? current.current;
          // Only when the server took this turn. If `ask` was rejected,
          // the message it was carrying is on its way back to the head of
          // the queue — flushing now would send the one behind it first
          // and deliver the two out of the order they were typed.
          if (accepted && settled && !settled.pending) flush(settled);
        } else {
          flushView();
        }
      }
    }
    // A deleted chat consumed the turn: handing the message back would
    // queue it for a conversation that no longer exists.
    // Asked again here: the delete may have landed during the refresh.
    return accepted || gone || removed.current.has(id);
  };

  // The conversation is handed in rather than read from state: the
  // `setActive` that just ran may not have re-rendered yet, and a
  // `deliver` that reads `active` as null opens a second conversation
  // and sends the queued message into it.
  // A null conversation is the blank chat on screen, whose first queued
  // message opens it.
  const flush = (conversation: Conversation | null) => {
    // Only this conversation's messages. `busy` is global, so a turn
    // running in A while the user opens B and types puts B's message in
    // the same queue — and A's teardown would then deliver it into A.
    // An exact match, `null` included: a message typed during the very
    // first send is re-tagged with that chat's id once it exists (see
    // `deliver`), so an untagged one only ever belongs to the blank chat.
    const next = queue.current.find(
      (message) => message.conversationId === (conversation?.id ?? blankKey()),
    );
    if (!next) return;

    queue.current = queue.current.filter((message) => message.id !== next.id);
    setQueued(queue.current);
    let back = next;
    void deliverLatest
      .current(next.text, next.attachments, conversation ?? undefined, (id) => {
        back = { ...next, conversationId: id };
      })
      .then((sent) => {
        if (sent) return;
        // Put it back where it was rather than losing it. Removing it first
        // is what keeps a second flush from picking up the same message,
        // but it means a send that never reached the server would otherwise
        // vanish with nothing but an error banner to show for it.
        putBack(back);
      });
  };

  // Drains the queue for whatever is on screen once a turn that was
  // running elsewhere lets go of the page. Skipped mid-open, when the
  // chat being opened has not arrived yet, and behind a parked
  // confirmation, which the server would refuse a message behind.
  const flushView = () => {
    const view = current.current;
    if ((view?.id ?? null) !== viewing.current || view?.pending) return;
    flush(view);
  };

  // The running turn, which is not necessarily the chat on screen.
  const stop = async () => {
    // A turn whose chat is still being created has nothing to stop yet —
    // and falling back to the chat on screen would stop the wrong one.
    const id = turn.current ? turn.current.id : active?.id;
    if (!id) return;
    try {
      await stopTurn(id);
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
    // Told the id of a chat created for this message, so a retry goes
    // back to that chat rather than to whatever is on screen by then.
    bind?: (id: string) => void,
  ): Promise<boolean> => {
    const composed = compose(text, attachments);
    // The ref, not `active`: a flush from another render's teardown may
    // call a `deliver` that closed over a chat since deleted.
    let conversation = known ?? current.current;
    // `busy` is React state set inside `run`, which on a first message
    // only runs after `createConversation` resolves — two sends inside
    // that window would both see an idle chat and open two conversations.
    // A ref latches synchronously, which is the whole point.
    const mine: { id: string | null } = { id: conversation?.id ?? null };
    turn.current = mine;
    const release = () => {
      if (turn.current === mine) turn.current = null;
    };
    const draft = conversation ? null : blankKey();
    if (draft) creating.current.add(draft);
    try {
      if (!conversation) {
        const created = await createConversation();
        conversation = created;
        mine.id = created.id;
        bind?.(created.id);
        // Anything typed into this blank chat while it was being created
        // was for it — and only this one.
        queue.current = queue.current.map((message) =>
          message.conversationId === draft ? { ...message, conversationId: created.id } : message,
        );
        setQueued(queue.current);
        if (draft) creating.current.delete(draft);
        // Only onto a screen still showing the blank chat it was typed
        // into. Someone who opened another chat while this was being
        // created keeps what they opened; the new chat joins the list.
        if (viewing.current === null && blankKey() === draft) adopt(created);
        else setConversations((list) => [created, ...list.filter((c) => c.id !== created.id)]);
        tracker.track('chat_started', { surface: 'web' });
      }
    } catch (e) {
      if (draft) creating.current.delete(draft);
      onFailure(e);
      // A blank chat the person has already left will never be created
      // now: its messages have nowhere to go, including the one this
      // call is about to hand back.
      if (draft && draft !== blankKey()) {
        removed.current.add(draft);
        queue.current = queue.current.filter((message) => message.conversationId !== draft);
        setQueued(queue.current);
      }
      release();
      // Nothing else will drain what the person queued in the chat they
      // moved on to. Their own blank chat is left alone: the caller puts
      // this message back at its head first, so the ones typed after it
      // cannot overtake it.
      if (draft && draft !== blankKey() && turn.current === null) flushView();
      return false;
    }

    const id = conversation.id;
    if (viewing.current === id) setMessages((list) => [...list, optimistic(composed, list.length)]);
    try {
      // The mode of the chat this is going to. `mode` is the picker, which
      // is only that chat's while it is the one on screen: a queued message
      // flushed the moment its chat is opened would otherwise go out under
      // the previous chat's mode — `auto` where this chat asked for
      // `manual` is a skipped confirmation.
      const sendMode = known && known.id !== active?.id ? (known.mode ?? 'manual') : mode;
      const here = await deviceLocation.current();
      return await run(id, () =>
        sendMessage(id, composed, withLocation(pageContext(), here), sendMode),
      );
    } finally {
      release();
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
      // `viewing`, not `active`: typed while a chat is still opening, it
      // is for the chat being opened, and waits for it (see `opening`).
      conversationId: viewing.current ?? blankKey(),
      text,
      attachments,
    };

    // The ref, not `busy`: it is claimed before the state catches up and
    // released by whichever of a turn's end or its chat's deletion comes
    // first.
    // Mid-open the chat this is for has not arrived yet; `open` sends
    // what waited once it has.
    const opening = viewing.current !== (current.current?.id ?? null);
    const idle = turn.current === null && pending === null && !opening;
    // This chat's backlog is part of "idle" on purpose. Without it a
    // message typed while earlier ones are waiting jumps the queue and
    // arrives before them — reachable whenever a flush was interrupted
    // and left chips behind. Other chats' chips wait for their own chat.
    const backlog = queue.current.some((m) => m.conversationId === message.conversationId);
    if (idle && !backlog) {
      let back = message;
      void deliver(text, attachments, undefined, (id) => {
        back = { ...message, conversationId: id };
      }).then((sent) => {
        if (sent) return;
        // The composer has already cleared itself, so a rejected POST
        // would otherwise take the message with it. It becomes a chip
        // instead — visible, cancelable, and picked up by the next
        // flush, which beats restoring text into a box the user has
        // probably started typing in again.
        putBack(back);
      });
      return;
    }

    queue.current = [...queue.current, message];
    setQueued(queue.current);

    // Queued while nothing is running means an earlier flush was
    // interrupted. Draining now — after appending, so order holds — is
    // what gets the backlog moving again without asking the user to
    // understand any of this.
    if (idle) flush(current.current);
  };

  const cancelQueued = (id: string) => {
    queue.current = queue.current.filter((message) => message.id !== id);
    setQueued(queue.current);
  };

  const answer = async (approved: boolean) => {
    // One turn at a time per tab; the buttons are disabled while one runs,
    // and this covers the instant before `busy` catches up.
    if (!active || !pending || turn.current) return;
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

  // The running tool's own sentence, for the pane's status line.
  const working = [...(live?.tools ?? [])].reverse().find((t) => t.ok === undefined)?.doing ?? null;

  return (
    <div className="mx-auto flex h-[calc(100dvh-4rem)] w-full max-w-7xl">
      <History
        conversations={conversations}
        activeId={active?.id ?? null}
        open={historyOpen}
        onOpen={open}
        onNew={startNew}
        onDelete={remove}
      />

      {/* Under `lg` the pane and the transcript share one column and the
          person picks which is showing; from `lg` up both are drawn. */}
      <main className={`${paneOpen ? 'hidden lg:flex' : 'flex'} min-w-0 flex-1 flex-col`}>
        <header className="flex items-center justify-between border-b border-zinc-200 px-bw-4 py-bw-3">
          <h1 className="truncate text-bw-lg font-bold text-zinc-900">
            {active?.title ?? 'New chat'}
          </h1>
          <div className="flex items-center gap-bw-2">
            <ModePicker mode={mode} onChange={changeMode} />
            <button
              type="button"
              onClick={() => setHistoryOpen((v) => !v)}
              className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 md:hidden"
            >
              History
            </button>
            {pane ? (
              <button
                type="button"
                data-testid="pane-toggle"
                onClick={() => setPaneOpen(true)}
                className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 lg:hidden"
              >
                Results
              </button>
            ) : null}
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
          queued={queued.filter((m) => m.conversationId === (active?.id ?? blankKey()))}
          onSend={send}
          onCancelQueued={cancelQueued}
          location={{ status: deviceLocation.status, onToggle: deviceLocation.toggle }}
        />
      </main>

      <aside
        className={`${paneOpen ? 'flex' : 'hidden'} min-w-0 flex-1 flex-col border-l border-zinc-200 lg:flex lg:w-80 lg:flex-none xl:w-[26rem] 2xl:w-[30rem]`}
      >
        <ResultsPane
          pane={pane}
          revision={paneRevision}
          working={working}
          onClose={() => setPaneOpen(false)}
        />
      </aside>
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
      {/* The chat's only showing of the site-wide disclaimer: here, on an
          empty conversation, rather than standing under the composer for
          the whole of every chat. Read before the first question is
          asked, which is where it does its work. */}
      <DisclaimerNote className="mt-bw-4 border-t border-zinc-200 pt-bw-3" />
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
  const [confirmingId, setConfirmingId] = useState<string | null>(null);

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
        {conversations.map((conversation) =>
          conversation.id === confirmingId ? (
            // Inline rather than a browser dialog, like deleting a review: the
            // question sits where the click was, and a delete cannot be undone.
            <li
              key={conversation.id}
              className="flex items-center gap-bw-2 rounded-bw-md bg-zinc-50 px-bw-2 py-bw-2 text-bw-sm"
            >
              <span className="flex-1 truncate text-zinc-600">Delete this chat?</span>
              <button
                type="button"
                onClick={() => {
                  setConfirmingId(null);
                  onDelete(conversation.id);
                }}
                className="font-semibold text-danger hover:underline"
              >
                Delete
              </button>
              <button
                type="button"
                onClick={() => setConfirmingId(null)}
                className="font-semibold text-zinc-400 hover:text-zinc-600"
              >
                Cancel
              </button>
            </li>
          ) : (
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
                onClick={() => setConfirmingId(conversation.id)}
                className="px-bw-1 text-zinc-300 hover:text-danger"
              >
                ×
              </button>
            </li>
          ),
        )}
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
 *  from — a restaurant page is the case that matters.
 *
 * Location-based URLs — the slug is now the 4th segment
 * (`/restaurants/<country>/<region>/<city>/<slug>`). The old 1-segment
 * shape (`/restaurants/<slug>`, still reachable during the redirect
 * window and from any stale referrer) is tried as a fallback, anchored so
 * a location listing (`/restaurants/usa/colorado`) or `/restaurants/new`
 * isn't read as a restaurant. */
function pageContext(): PageContext | undefined {
  if (typeof document === 'undefined') return undefined;
  const from = new URL(document.referrer || document.location.href, document.location.href);
  if (from.origin !== document.location.origin) return undefined;
  const restaurant =
    /^\/restaurants\/[^/]+\/[^/]+\/[^/]+\/([^/]+)/.exec(from.pathname)?.[1] ??
    /^\/restaurants\/(?!new\/?$)([^/]+)(?:\/(?:scan|claim|suggestions|items\/[^/]+))?\/?$/.exec(
      from.pathname,
    )?.[1];
  return restaurant ? { path: from.pathname, restaurant } : undefined;
}

function withLocation(
  context: PageContext | undefined,
  location: DeviceLocation | undefined,
): PageContext | undefined {
  return location ? { ...context, location } : context;
}

function optimistic(text: string, index: number): ChatMessage {
  return {
    id: `pending-${index}`,
    role: 'user',
    position: index,
    blocks: [{ type: 'text', text }],
  };
}
