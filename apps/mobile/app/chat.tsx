import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  answerConfirmation,
  compose,
  createConversation,
  fetchEvents,
  getConversation,
  sendMessage,
  setConversationMode,
  stopTurn,
  uploadAttachment,
  type Attachment,
  type ChatEvent,
  type ChatMessage,
  type ChatMode,
  type Conversation,
  type PendingTool,
} from '../lib/api/chat';
import { getJwt } from '../lib/auth';
import { useTracker } from '../lib/tracker-context';

/**
 * The chat, on mobile. Restores the scan path the app lost in M2.
 *
 * **Polls where web streams.** React Native's fetch is XHR-backed and
 * exposes no readable response body, so the SSE relay is not consumable
 * here; `fetchEvents` reads the same rows as JSON and `running` says when
 * to stop asking. The narration is identical either way — the relay is
 * just a long-lived reader over the same table.
 *
 * Two contracts carried over from web deliberately, because they are the
 * safety story rather than styling:
 *
 *   * **The confirmation gate answers with a fingerprint**, so a screen
 *     left open on an earlier prompt cannot approve whatever is parked
 *     now.
 *   * **After a turn the conversation is refetched** rather than stitched
 *     from the narration, so what is on screen is what the server stored.
 */
const POLL_MS = 900;
// A worker that never picks the turn up would otherwise poll forever.
const MAX_POLL_MS = 5 * 60 * 1000;

/**
 * How much the assistant may do without asking. Short labels because
 * four of them share a phone's width; the full sentence is the
 * accessibility hint, which is also where a screen reader wants it.
 */
const MODES: { value: ChatMode; label: string; hint: string }[] = [
  { value: 'planning', label: 'Plan', hint: 'Reads only. Proposes changes, never makes them.' },
  { value: 'manual', label: 'Manual', hint: 'Asks before anything destructive.' },
  // Says what it waives, not just what it keeps. "Still asks before a
  // delete" was true and read as a much narrower promise than it is.
  {
    value: 'accept_edits',
    label: 'Edits',
    hint: 'Menu and profile changes go through without asking — including removing something from your avoid list. Still asks before a delete.',
  },
  { value: 'auto', label: 'Auto', hint: 'Never asks.' },
];

/** A message typed while the assistant was busy. */
interface QueuedMessage {
  id: string;
  /** The conversation it was typed into. `busy` is global, so a turn
   *  running in one chat must not deliver a message meant for another —
   *  null means "the one being created right now". */
  conversationId: string | null;
  text: string;
  attachments: Attachment[];
}

export default function ChatScreen() {
  const tracker = useTracker();
  const [conversation, setConversation] = useState<Conversation | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pending, setPending] = useState<PendingTool | null>(null);
  const [live, setLive] = useState<string[]>([]);
  const [draft, setDraft] = useState('');
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState<ChatMode>('manual');
  const [queued, setQueued] = useState<QueuedMessage[]>([]);
  const bottom = useRef<ScrollView>(null);
  // Read from inside `run`'s teardown, which closes over the render that
  // started the turn — by then the state is a minute stale. The refs are
  // current; the state is what draws.
  const queue = useRef<QueuedMessage[]>([]);
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

  const requireJwt = useCallback(async (): Promise<string | null> => {
    const jwt = await getJwt();
    if (!jwt) router.replace('/login?next=%2Fchat');
    return jwt;
  }, []);

  useEffect(() => {
    void requireJwt();
  }, [requireJwt]);

  const adopt = (next: Conversation) => {
    setConversation(next);
    setMessages(next.messages ?? []);
    setPending(next.pending);
    // Absent reads as `manual`, matching `ModePolicy.resolve` — an older
    // API that does not send one must not leave the picker claiming a
    // looser gate than the server is applying.
    //
    // Skipped while a switch is in the air: a turn's teardown refresh can
    // be served before the PATCH commits, and adopting that response
    // would snap the picker back to the mode the user just left — then
    // stamp it onto the next send, re-enabling writes they turned off.
    if (!switchingMode.current) setMode(next.mode ?? 'manual');
  };

  const refresh = async (jwt: string, id: string): Promise<Conversation | null> => {
    try {
      const next = await getConversation(jwt, id);
      adopt(next);
      return next;
    } catch (e) {
      setError((e as Error).message);
      return null;
    }
  };

  /** Reads the narration until the server says nothing is in flight. */
  const watch = async (jwt: string, id: string, after: number) => {
    let cursor = after;
    const deadline = Date.now() + MAX_POLL_MS;

    for (;;) {
      const page = await fetchEvents(jwt, id, cursor);
      for (const event of page.events) {
        cursor = event.position;
        setLive((lines) => describe(event, lines));
      }
      if (!page.running || Date.now() > deadline) return;
      await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    }
  };

  // Answers whether the server *accepted* the turn, which is a different
  // question from whether it went well. Once `ask` resolves the message is
  // recorded server-side and polling it is bookkeeping — a poll that fails
  // must not read as "nothing was sent", or the caller restores a message
  // that is already on its way.
  const run = async (
    id: string,
    ask: (jwt: string) => Promise<{ after: number }>,
  ): Promise<boolean> => {
    const jwt = await requireJwt();
    // Navigating to login, so the screen holding the draft is going away.
    if (!jwt) return true;

    setBusy(true);
    setError(null);
    setLive([]);
    const startedAt = Date.now();
    let accepted = false;
    try {
      const { after } = await ask(jwt);
      accepted = true;
      await watch(jwt, id, after);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLive([]);
      setBusy(false);
      tracker.track('chat_turn_completed', {
        outcome: 'done',
        tool_count: 0,
        duration_ms: Date.now() - startedAt,
      });
      const next = await refresh(jwt, id);
      // Drained from the teardown of the turn that was blocking it, not
      // from an effect on `busy` — an effect fires on the render where
      // `busy` flips false and the queue has already been shortened,
      // which is one render before the next turn sets it back, so two
      // queued messages would leave together.
      //
      // Not while a confirmation is parked: the server refuses a message
      // behind one, and the queued message is quite often the user
      // changing their mind about the thing being asked.
      //
      // `?? conversation` covers a failed refresh. Without it a failed
      // `getConversation` strands the whole queue: the turn is over,
      // `busy` is false, and nothing else drains it.
      const settled = next ?? conversation;
      // Only when the server took this turn. If `ask` was rejected, the
      // message it was carrying is on its way back to the queue, and
      // flushing now would send the one behind it first.
      if (accepted && settled && !settled.pending) flush(settled);
    }
    return accepted;
  };

  // The conversation is handed in rather than read from state: the
  // `setConversation` that just ran may not have re-rendered yet, and a
  // deliver that reads it as null opens a second conversation.
  const flush = (active: Conversation) => {
    // Only this conversation's messages, and `null` for one typed during
    // the very first send, before the conversation existed.
    const next = queue.current.find(
      (message) => message.conversationId === active.id || message.conversationId === null,
    );
    if (!next) return;

    queue.current = queue.current.filter((message) => message.id !== next.id);
    setQueued(queue.current);
    void deliverLatest.current(next.text, next.attachments, active).then((sent) => {
      if (sent) return;
      // Put it back at the head rather than losing it. Dequeuing first is
      // what keeps a second flush from picking up the same message, but a
      // send that never reached the server would otherwise vanish with
      // nothing but an error banner to show for it.
      queue.current = [next, ...queue.current];
      setQueued(queue.current);
    });
  };

  // Answers whether the message actually left, so a caller that already
  // cleared the input can put it back rather than eating what someone
  // typed because the network was down.
  const deliver = async (
    text: string,
    files: Attachment[],
    known?: Conversation,
  ): Promise<boolean> => {
    const composed = compose(text, files);
    if (!composed) return false;

    const jwt = await requireJwt();
    // Not a failure worth restoring for — this navigates to login, and
    // the screen holding the draft is going away.
    if (!jwt) return true;

    let active = known ?? conversation;
    // `busy` is React state set inside `run`, which on a first message
    // only runs after `createConversation` resolves — two taps inside
    // that window would both see an idle chat and open two conversations.
    // A ref latches synchronously, which is the whole point.
    inFlight.current = true;
    if (!active) {
      try {
        active = await createConversation(jwt);
        adopt(active);
        tracker.track('chat_started', { surface: Platform.OS === 'android' ? 'android' : 'ios' });
      } catch (e) {
        setError((e as Error).message);
        inFlight.current = false;
        return false;
      }
    }

    const id = active.id;
    try {
      return await run(id, (token) => sendMessage(token, id, composed, mode));
    } finally {
      inFlight.current = false;
    }
  };
  deliverLatest.current = deliver;

  // What the Send button calls. Either this goes now or it waits its
  // turn — the button says which, and a chip appears when it waited.
  const submit = () => {
    const text = draft.trim();
    if (!text && attachments.length === 0) return;

    const files = attachments;
    setDraft('');
    setAttachments([]);

    // Cleared now rather than after the send lands: waiting leaves the
    // text sitting in the box while the conversation is created, which
    // reads as a dropped tap. It comes back if the send never happened.
    //
    // An empty queue is part of "idle" on purpose — without it a message
    // typed while a backlog is waiting jumps ahead of messages typed
    // earlier, which is reachable whenever a flush was interrupted.
    const idle = !busy && !inFlight.current && pending === null;
    if (idle && queue.current.length === 0) {
      void deliver(text, files).then((sent) => {
        if (sent) return;
        setDraft(text);
        setAttachments(files);
      });
      return;
    }

    // The id is a React key and a cancel handle, nothing more: it only
    // has to be unique among the handful queued at once.
    const message: QueuedMessage = {
      id: `queued-${Date.now()}-${queue.current.length}`,
      conversationId: conversation?.id ?? null,
      text,
      attachments: files,
    };
    queue.current = [...queue.current, message];
    setQueued(queue.current);

    // Queued while nothing is running means an earlier flush was
    // interrupted. Draining now — after appending, so order holds — gets
    // the backlog moving without asking the user to understand any of it.
    if (idle && conversation) flush(conversation);
  };

  const cancelQueued = (id: string) => {
    queue.current = queue.current.filter((message) => message.id !== id);
    setQueued(queue.current);
  };

  const answer = async (approved: boolean) => {
    if (!conversation || !pending) return;
    const { fingerprint } = pending;
    setPending(null);
    tracker.track('chat_confirmed', { approved });
    await run(conversation.id, (jwt) =>
      answerConfirmation(jwt, conversation.id, approved, fingerprint, mode),
    );
  };

  // Persisted so the picker survives a reload; a conversation that does
  // not exist yet has nowhere to persist it, and the first `sendMessage`
  // carries it instead.
  const changeMode = async (next: ChatMode) => {
    const previous = mode;
    setMode(next);
    if (!conversation) return;

    const jwt = await getJwt();
    if (!jwt) return;
    // Switch twice quickly and two PATCHes are in the air with no
    // ordering between them; the older one landing last would leave the
    // picker and the server disagreeing about which gate is on. The
    // counter makes every response except the newest a no-op.
    const ticket = (modeTicket.current += 1);
    switchingMode.current = true;
    try {
      await setConversationMode(jwt, conversation.id, next);
    } catch (e) {
      if (ticket !== modeTicket.current) return;
      setMode(previous);
      setError((e as Error).message);
    } finally {
      if (ticket === modeTicket.current) switchingMode.current = false;
    }
  };

  const stop = async () => {
    const jwt = await getJwt();
    if (!jwt || !conversation) return;
    try {
      await stopTurn(jwt, conversation.id);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  // Photo capture goes through expo-image-picker rather than expo-camera,
  // matching the review flow: it gives the system camera UI and the
  // library picker from one API, and a menu photo is a still.
  const attach = async (source: 'camera' | 'library') => {
    const jwt = await requireJwt();
    if (!jwt) return;

    const permission =
      source === 'camera'
        ? await ImagePicker.requestCameraPermissionsAsync()
        : await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (permission.status !== 'granted') {
      Alert.alert('Permission needed', 'Enable access in Settings to attach a menu photo.');
      return;
    }

    const res =
      source === 'camera'
        ? await ImagePicker.launchCameraAsync({ quality: 0.8 })
        : await ImagePicker.launchImageLibraryAsync({
            mediaTypes: ImagePicker.MediaTypeOptions.Images,
            quality: 0.8,
          });
    const asset = !res.canceled ? res.assets[0] : undefined;
    if (!asset) return;

    try {
      const uploaded = await uploadAttachment(jwt, {
        uri: asset.uri,
        name: asset.fileName ?? 'menu.jpg',
        type: asset.mimeType ?? 'image/jpeg',
      });
      setAttachments((current) => [...current, uploaded]);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <KeyboardAvoidingView
      style={styles.screen}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        ref={bottom}
        style={styles.transcript}
        contentContainerStyle={styles.transcriptContent}
        onContentSizeChange={() => bottom.current?.scrollToEnd({ animated: true })}
      >
        {messages.length === 0 && !busy ? <Welcome /> : null}

        {messages.map((message) => (
          <MessageRow key={message.id} message={message} />
        ))}

        {live.map((line, index) => (
          <Text key={index} style={styles.live} testID="chat-live">
            {line}
          </Text>
        ))}

        {busy && live.length === 0 ? <ActivityIndicator testID="chat-thinking" /> : null}

        {pending ? <ConfirmPrompt tool={pending} busy={busy} onAnswer={answer} /> : null}

        {error ? (
          <Text style={styles.error} testID="chat-error">
            {error}
          </Text>
        ) : null}
      </ScrollView>

      <View style={styles.modes} testID="chat-modes">
        {MODES.map((option) => (
          <Pressable
            key={option.value}
            onPress={() => void changeMode(option.value)}
            accessibilityRole="button"
            accessibilityLabel={`${option.label} mode`}
            accessibilityHint={option.hint}
            accessibilityState={{ selected: mode === option.value }}
            style={[styles.mode, mode === option.value && styles.modeOn]}
          >
            <Text style={[styles.modeLabel, mode === option.value && styles.modeLabelOn]}>
              {option.label}
            </Text>
          </Pressable>
        ))}
      </View>

      {/* Someone in `auto` has switched off the only place a destructive
          call stops for a human. That has to be readable without opening
          anything to check. */}
      {mode !== 'manual' ? (
        <Text style={[styles.modeNotice, mode === 'auto' && styles.modeNoticeLoud]} testID="chat-mode-notice">
          {MODES.find((m) => m.value === mode)?.hint}
        </Text>
      ) : null}

      {/* Cancelable, because "queued" and "sent" are different promises —
          and the commonest reason to want one back is the assistant
          answering it unprompted while the user was still typing. */}
      {queued.length > 0 ? (
        <View style={styles.chips} testID="chat-queued">
          {queued.map((message) => (
            <Pressable
              key={message.id}
              onPress={() => cancelQueued(message.id)}
              accessibilityRole="button"
              accessibilityLabel={`Cancel queued message: ${message.text || 'attachments'}`}
            >
              <Text style={styles.queuedChip}>
                ⏳ {message.text || `${message.attachments.length} attachment(s)`} ✕
              </Text>
            </Pressable>
          ))}
        </View>
      ) : null}

      {attachments.length > 0 ? (
        <View style={styles.chips} testID="chat-attachments">
          {attachments.map((file) => (
            <Text key={file.id} style={styles.chip}>
              {file.filename}
            </Text>
          ))}
        </View>
      ) : null}

      {busy ? (
        <Pressable onPress={() => void stop()} style={styles.stop} accessibilityRole="button">
          <Text style={styles.stopLabel}>Stop</Text>
        </Pressable>
      ) : null}

      <View style={styles.composer}>
        <Pressable
          onPress={() => void attach('camera')}
          accessibilityLabel="Take a menu photo"
          style={styles.iconButton}
        >
          <Text style={styles.icon}>📷</Text>
        </Pressable>
        <Pressable
          onPress={() => void attach('library')}
          accessibilityLabel="Attach a menu photo"
          style={styles.iconButton}
        >
          <Text style={styles.icon}>🖼️</Text>
        </Pressable>
        {/* Deliberately not gated on whether a turn is running. The input
            used to go dead for the length of one — a minute or more of a
            menu scan — and a thought that arrived during it had nowhere
            to go but the user's memory. It queues instead. */}
        <TextInput
          style={styles.input}
          value={draft}
          onChangeText={setDraft}
          placeholder={
            busy || pending !== null
              ? 'Type the next one — it will send when this finishes'
              : 'Ask about a menu, or add one'
          }
          accessibilityLabel="Message"
          multiline
        />
        <Pressable onPress={submit} accessibilityRole="button" style={styles.send}>
          <Text style={styles.sendLabel}>{busy || pending !== null ? 'Queue' : 'Send'}</Text>
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

/** One narration line. The tool's own sentence when it declared one. */
function describe(event: ChatEvent, lines: string[]): string[] {
  if (event.type === 'tool_use') return [...lines, event.doing ?? `Running ${event.name}`];
  if (event.type === 'error') return [...lines, event.message ?? 'Something went wrong.'];
  return lines;
}

function Welcome() {
  return (
    <View testID="chat-welcome">
      <Text style={styles.welcomeTitle}>Ask about a menu, or add one.</Text>
      <Text style={styles.welcomeLine}>“What can I eat at Ninis Taqueria?”</Text>
      <Text style={styles.welcomeLine}>“Add cilantro to my avoid list.”</Text>
      <Text style={styles.welcomeLine}>Take a photo of a menu and I’ll read it.</Text>
    </View>
  );
}

function MessageRow({ message }: { message: ChatMessage }) {
  // Tool results ride on a user-role message because that is the Messages
  // API shape, not because a person typed them.
  const visible = message.blocks.filter((b) => b.type === 'text');
  if (visible.length === 0) return null;

  const text = visible.map((b) => (b.type === 'text' ? b.text : '')).join('\n');
  const mine = message.role === 'user';

  return (
    <View style={[styles.bubble, mine ? styles.mine : styles.theirs]} testID="chat-message">
      <Text style={mine ? styles.mineText : styles.theirsText}>{text}</Text>
    </View>
  );
}

/**
 * The human gate. Nothing that publishes, deletes, or changes what other
 * people are shown runs because a model decided to — the server parks the
 * call and this is where the person answers.
 */
function ConfirmPrompt({
  tool,
  busy,
  onAnswer,
}: {
  tool: PendingTool;
  busy: boolean;
  onAnswer: (approved: boolean) => void;
}) {
  return (
    <View style={styles.confirm} testID="chat-confirm">
      <Text style={styles.confirmText}>{tool.prompt ?? `Allow ${tool.name}?`}</Text>
      <View style={styles.confirmRow}>
        <Pressable
          disabled={busy}
          onPress={() => onAnswer(true)}
          accessibilityRole="button"
          style={styles.confirmYes}
        >
          <Text style={styles.confirmYesLabel}>Yes, do it</Text>
        </Pressable>
        <Pressable
          disabled={busy}
          onPress={() => onAnswer(false)}
          accessibilityRole="button"
          style={styles.confirmNo}
        >
          <Text style={styles.confirmNoLabel}>No</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  transcript: { flex: 1 },
  transcriptContent: { padding: space[4], gap: space[3] },
  welcomeTitle: { fontSize: fontSize.base, fontWeight: '600', color: colors.text },
  welcomeLine: { fontSize: fontSize.sm, color: colors.textMuted, marginTop: space[1] },
  bubble: { borderRadius: 12, paddingVertical: space[2], paddingHorizontal: space[3], maxWidth: '85%' },
  mine: { alignSelf: 'flex-end', backgroundColor: colors.bite },
  theirs: { alignSelf: 'flex-start', backgroundColor: colors.bgAlt },
  mineText: { color: colors.bg, fontSize: fontSize.base },
  theirsText: { color: colors.text, fontSize: fontSize.base },
  live: { fontSize: fontSize.sm, color: colors.textMuted, fontStyle: 'italic' },
  error: { fontSize: fontSize.sm, color: colors.danger },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: space[1], paddingHorizontal: space[4] },
  chip: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    backgroundColor: colors.bgAlt,
    borderRadius: 8,
    paddingHorizontal: space[2],
    paddingVertical: space[1],
  },
  queuedChip: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: colors.border,
    borderRadius: 8,
    paddingHorizontal: space[2],
    paddingVertical: space[1],
  },
  modes: { flexDirection: 'row', gap: space[1], paddingHorizontal: space[4], paddingBottom: space[1] },
  mode: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 999,
    paddingHorizontal: space[2],
    paddingVertical: space[1],
  },
  modeOn: { borderColor: colors.bite, backgroundColor: colors.bgAlt },
  modeLabel: { fontSize: fontSize.xs, color: colors.textMuted },
  modeLabelOn: { color: colors.text, fontWeight: '700' },
  modeNotice: { fontSize: fontSize.xs, color: colors.textMuted, paddingHorizontal: space[4], paddingBottom: space[1] },
  modeNoticeLoud: { color: colors.danger },
  stop: { alignSelf: 'flex-start', paddingHorizontal: space[4], paddingBottom: space[2] },
  stopLabel: { fontSize: fontSize.sm, color: colors.textMuted },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: space[2],
    padding: space[3],
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  iconButton: { paddingVertical: space[2] },
  icon: { fontSize: fontSize.lg },
  input: {
    flex: 1,
    maxHeight: 120,
    fontSize: fontSize.base,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    paddingHorizontal: space[3],
    paddingVertical: space[2],
  },
  send: { backgroundColor: colors.bite, borderRadius: 12, paddingHorizontal: space[4], paddingVertical: space[2] },
  sendDisabled: { opacity: 0.5 },
  sendLabel: { color: colors.bg, fontWeight: '700' },
  confirm: {
    borderWidth: 1,
    borderColor: colors.warn,
    borderRadius: 12,
    padding: space[3],
    gap: space[2],
  },
  confirmText: { fontSize: fontSize.base, color: colors.text },
  confirmRow: { flexDirection: 'row', gap: space[2] },
  confirmYes: { backgroundColor: colors.bite, borderRadius: 10, paddingHorizontal: space[3], paddingVertical: space[2] },
  confirmYesLabel: { color: colors.bg, fontWeight: '700' },
  confirmNo: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 10,
    paddingHorizontal: space[3],
    paddingVertical: space[2],
  },
  confirmNoLabel: { color: colors.text },
});
