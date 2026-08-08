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
  stopTurn,
  uploadAttachment,
  type Attachment,
  type ChatEvent,
  type ChatMessage,
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
  const bottom = useRef<ScrollView>(null);

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
  };

  const refresh = async (jwt: string, id: string) => {
    try {
      adopt(await getConversation(jwt, id));
    } catch (e) {
      setError((e as Error).message);
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

  const run = async (id: string, ask: (jwt: string) => Promise<{ after: number }>) => {
    const jwt = await requireJwt();
    if (!jwt) return;

    setBusy(true);
    setError(null);
    setLive([]);
    const startedAt = Date.now();
    try {
      const { after } = await ask(jwt);
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
      await refresh(jwt, id);
    }
  };

  const send = async () => {
    const text = compose(draft.trim(), attachments);
    if (!text) return;

    const jwt = await requireJwt();
    if (!jwt) return;

    let active = conversation;
    if (!active) {
      try {
        active = await createConversation(jwt);
        adopt(active);
        tracker.track('chat_started', { surface: Platform.OS === 'android' ? 'android' : 'ios' });
      } catch (e) {
        setError((e as Error).message);
        return;
      }
    }

    setDraft('');
    setAttachments([]);
    await run(active.id, (token) => sendMessage(token, active.id, text));
  };

  const answer = async (approved: boolean) => {
    if (!conversation || !pending) return;
    const { fingerprint } = pending;
    setPending(null);
    tracker.track('chat_confirmed', { approved });
    await run(conversation.id, (jwt) =>
      answerConfirmation(jwt, conversation.id, approved, fingerprint),
    );
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
        <TextInput
          style={styles.input}
          value={draft}
          onChangeText={setDraft}
          editable={!busy && pending === null}
          placeholder="Ask about a menu, or add one"
          accessibilityLabel="Message"
          multiline
        />
        <Pressable
          onPress={() => void send()}
          disabled={busy || pending !== null}
          accessibilityRole="button"
          style={[styles.send, (busy || pending !== null) && styles.sendDisabled]}
        >
          <Text style={styles.sendLabel}>Send</Text>
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
