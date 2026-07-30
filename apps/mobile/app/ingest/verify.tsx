import { useEffect, useState, useCallback } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { getJwt } from '../../lib/auth';
import {
  decideIngestionItem,
  getIngestionRun,
  listIngestionItems,
  type IngestionItemPayload,
  type IngestionRunPayload,
} from '../../lib/api/ingestion-runs';

const POLL_INTERVAL_MS = 2_000;

// Phase 7.3 — human copy per pipeline stage so the wait reads as
// progress, not a stuck spinner. Keys are IngestionRunPayload statuses.
const STAGE_COPY: Record<string, string> = {
  queued: 'Waiting in line…',
  extracting: 'Reading the menu…',
  resolving: 'Matching ingredients & tags…',
};

/**
 * Phase 2.7 + 4.1 — swipe-verify deck.
 *
 * Routed at `/ingest/verify?runId=...`. JWT comes from the keychain
 * (Phase 4.1 — `getJwt()` from lib/auth). While the run is in
 * `:queued / :extracting / :resolving`, polls every 2s. Once status
 * hits `:staged`, fetches the items and shows a one-at-a-time card
 * with Accept / Reject / Edit buttons.
 *
 * Phase 2.7 shipped the tap-to-decide flow + the polling. The
 * Tinder-style swipe gestures (react-native-gesture-handler +
 * reanimated worklets) come in a follow-up after the on-device
 * testing pass — the data wiring is what matters for end-to-end.
 */
export default function VerifyScreen() {
  const params = useLocalSearchParams<{ runId?: string }>();
  const runId = params.runId ?? '';
  const [jwt, setJwtState] = useState<string | null>(null);
  const [authChecked, setAuthChecked] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getJwt().then((t) => {
      if (cancelled) return;
      setJwtState(t);
      setAuthChecked(true);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const [run, setRun] = useState<IngestionRunPayload | null>(null);
  const [items, setItems] = useState<IngestionItemPayload[]>([]);
  const [cursor, setCursor] = useState(0);
  const [editing, setEditing] = useState(false);
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');

  // Poll the run until staged, then load items. While the background AI
  // gap-fill pass is still running (enrichment_status: "pending"), keep
  // polling and merge fresher payloads into the deck by id — never
  // reorder or re-filter, so the card under the user's thumb stays put.
  useEffect(() => {
    if (!runId || !jwt) return;
    let cancelled = false;
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    // Hard stop (~10 min) so a wedged run can't poll the phone forever.
    let pollsLeft = 300;

    const schedule = () => {
      pollsLeft -= 1;
      if (pollsLeft > 0) timeoutId = setTimeout(poll, POLL_INTERVAL_MS);
    };

    const poll = async () => {
      try {
        const fresh = await getIngestionRun(runId, { jwt });
        if (cancelled) return;
        setRun(fresh);
        if (fresh.status === 'staged' || fresh.status === 'published') {
          const list = await listIngestionItems(runId, { jwt });
          if (cancelled) return;
          setItems((prev) =>
            prev.length === 0
              ? list.filter((it) => it.decision === 'pending')
              : prev.map((it) => list.find((f) => f.id === it.id) ?? it),
          );
          if (fresh.enrichment_status === 'pending') schedule();
          return;
        }
        if (fresh.status === 'failed') return;
        schedule();
      } catch (e) {
        if (cancelled) return;
        Alert.alert('Polling error', (e as Error).message);
      }
    };

    poll();
    return () => {
      cancelled = true;
      if (timeoutId) clearTimeout(timeoutId);
    };
  }, [runId, jwt]);

  const current = items[cursor];

  // Phase 7.3 — finishing the deck may trip the 80% auto-publish.
  // Refetch once so the done screen knows whether to celebrate.
  const deckDone = items.length > 0 && cursor >= items.length;
  useEffect(() => {
    if (!deckDone || !jwt) return;
    let cancelled = false;
    getIngestionRun(runId, { jwt })
      .then((fresh) => {
        if (!cancelled) setRun(fresh);
      })
      .catch(() => {
        // Non-fatal — the done screen falls back to the staged copy.
      });
    return () => {
      cancelled = true;
    };
  }, [deckDone, runId, jwt]);

  const decide = useCallback(
    async (decision: 'accepted' | 'rejected' | 'edited') => {
      if (!current || !jwt) return;
      try {
        const edits =
          decision === 'edited' || decision === 'accepted'
            ? { name: editName || current.name, description: editDescription || current.description || undefined }
            : undefined;
        await decideIngestionItem({
          runId,
          itemId: current.id,
          decision,
          edits,
          jwt,
        });
        setCursor((i) => i + 1);
        setEditing(false);
        setEditName('');
        setEditDescription('');
      } catch (e) {
        Alert.alert('Failed to record decision', (e as Error).message);
      }
    },
    [current, runId, jwt, editName, editDescription],
  );

  if (!runId) {
    return (
      <View style={styles.container}>
        <Text style={styles.body}>Missing runId query param.</Text>
      </View>
    );
  }

  if (authChecked && !jwt) {
    router.replace('/login?next=' + encodeURIComponent(`/ingest/verify?runId=${runId}`));
    return null;
  }
  if (!authChecked) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color={colors.bite} />
      </View>
    );
  }

  if (!run) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color={colors.bite} testID="initial-loading" />
        <Text style={styles.body}>Loading run…</Text>
      </View>
    );
  }

  if (run.status === 'failed') {
    return (
      <View style={styles.container}>
        <Text style={styles.headline}>Extraction failed</Text>
        <Text style={styles.body}>{run.failure_message}</Text>
      </View>
    );
  }

  if (run.status !== 'staged' && run.status !== 'published') {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color={colors.bite} testID="extracting-loading" />
        <Text style={styles.headline}>{STAGE_COPY[run.status] ?? `${run.status}…`}</Text>
        <Text style={styles.body}>
          Polling every {POLL_INTERVAL_MS / 1000}s. The deck opens as soon as the AI finishes.
        </Text>
      </View>
    );
  }

  if (items.length === 0) {
    return (
      <View style={styles.container}>
        <Text style={styles.headline}>Nothing to verify</Text>
        <Text style={styles.body}>
          Either every item is already decided, or the run produced no items.
        </Text>
        <ViewMenuButton restaurantId={run.restaurant_id} />
      </View>
    );
  }

  if (!current) {
    // Phase 7.3 — the end of the scan loop: deep-link into the
    // user's own filtered view of the menu they just scanned.
    const published = run.status === 'published';
    return (
      <View style={styles.container}>
        <Text style={styles.headline}>{published ? 'Menu published! 🎉' : 'All done!'}</Text>
        <Text style={styles.body}>
          {published
            ? 'Your scan is live. See it filtered to your preferences:'
            : `You decided on ${items.length} item${items.length === 1 ? '' : 's'}. The run ` +
              'auto-publishes at the 80% threshold — you can open the restaurant now.'}
        </Text>
        <ViewMenuButton restaurantId={run.restaurant_id} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>
        Item {cursor + 1} of {items.length}
      </Text>

      <ScrollView style={styles.card} contentContainerStyle={{ gap: space['3'] }}>
        <Text style={styles.headline} testID="card-name">
          {current.name}
        </Text>
        {current.description ? (
          <Text style={styles.body} testID="card-description">
            {current.description}
          </Text>
        ) : null}
        {current.section_name ? (
          <Text style={styles.muted}>Section: {current.section_name}</Text>
        ) : null}

        {current.addons_payload.length > 0 && (
          <>
            <View style={styles.divider} />
            <Text style={styles.label}>Add-ons</Text>
            {current.addons_payload.map((addon, i) => (
              <Text style={styles.row} key={`${addon.name}-${i}`}>
                + {addon.name}
                {addon.price_cents != null ? ` $${(addon.price_cents / 100).toFixed(2)}` : ''}
              </Text>
            ))}
          </>
        )}

        <View style={styles.divider} />
        <Text style={styles.label}>Ingredients</Text>
        {current.ingredients_payload.map((ing) => (
          <Text style={styles.row} key={ing.slug}>
            • {ing.slug} ({Math.round(ing.confidence * 100)}%)
          </Text>
        ))}
        {current.unresolved_ingredients.length > 0 && (
          <Text style={styles.warn}>
            Couldn't match: {current.unresolved_ingredients.join(', ')}
          </Text>
        )}

        <View style={styles.divider} />
        <Text style={styles.label}>Tags</Text>
        {current.tags_payload.map((tag) => (
          <Text style={styles.row} key={tag.slug}>
            • {tag.slug} ({Math.round(tag.confidence * 100)}%)
          </Text>
        ))}
        {current.unresolved_tags.length > 0 && (
          <Text style={styles.warn}>
            Couldn't match: {current.unresolved_tags.join(', ')}
          </Text>
        )}

        {editing && (
          <View style={{ gap: space['3'], marginTop: space['3'] }}>
            <TextInput
              accessibilityLabel="edit-name"
              placeholder="Override name"
              value={editName}
              onChangeText={setEditName}
              style={styles.input}
            />
            <TextInput
              accessibilityLabel="edit-description"
              placeholder="Override description"
              value={editDescription}
              onChangeText={setEditDescription}
              multiline
              style={[styles.input, { minHeight: 60 }]}
            />
          </View>
        )}
      </ScrollView>

      <View style={styles.actions}>
        <Pressable
          accessibilityLabel="reject"
          onPress={() => decide('rejected')}
          style={[styles.actionButton, { backgroundColor: colors.danger }]}
        >
          <Text style={styles.actionText}>✗ Reject</Text>
        </Pressable>
        <Pressable
          accessibilityLabel="edit"
          onPress={() => {
            if (editing) decide('edited');
            else {
              setEditName(current.name);
              setEditDescription(current.description ?? '');
              setEditing(true);
            }
          }}
          style={[styles.actionButton, { backgroundColor: colors.warn }]}
        >
          <Text style={styles.actionText}>{editing ? '✎ Save edit' : '✎ Edit'}</Text>
        </Pressable>
        <Pressable
          accessibilityLabel="accept"
          onPress={() => decide('accepted')}
          style={[styles.actionButton, { backgroundColor: colors.ok }]}
        >
          <Text style={styles.actionText}>✓ Accept</Text>
        </Pressable>
      </View>
    </View>
  );
}

function ViewMenuButton({ restaurantId }: { restaurantId: string }) {
  return (
    <Pressable
      accessibilityLabel="view-menu"
      onPress={() => router.replace(`/restaurants/${restaurantId}?from=scan`)}
      style={styles.viewMenuButton}
    >
      <Text style={styles.viewMenuText}>🍽 See the menu</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 60,
    paddingHorizontal: space['6'],
    backgroundColor: colors.bg,
    gap: space['3'],
  },
  eyebrow: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  card: {
    flex: 1,
    backgroundColor: colors.bgAlt,
    borderRadius: 16,
    padding: space['4'],
  },
  headline: {
    fontSize: fontSize['2xl'],
    fontWeight: '700',
    color: colors.text,
  },
  body: {
    fontSize: fontSize.base,
    color: colors.text,
  },
  muted: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
  },
  label: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  row: {
    color: colors.text,
    fontSize: fontSize.base,
  },
  warn: {
    color: colors.warn,
    fontSize: fontSize.sm,
  },
  divider: {
    height: 1,
    backgroundColor: colors.border,
    marginVertical: space['2'],
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: space['3'],
    fontSize: fontSize.base,
    color: colors.text,
    backgroundColor: colors.bg,
  },
  actions: {
    flexDirection: 'row',
    gap: space['3'],
    paddingVertical: space['4'],
  },
  actionButton: {
    flex: 1,
    paddingVertical: space['4'],
    borderRadius: 12,
    alignItems: 'center',
  },
  actionText: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.base,
  },
  viewMenuButton: {
    backgroundColor: colors.bite,
    paddingVertical: space['4'],
    borderRadius: 12,
    alignItems: 'center',
  },
  viewMenuText: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.base,
  },
});
