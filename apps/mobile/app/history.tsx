import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { router } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  fetchHistory,
  HistoryError,
  type HistoryVisit,
} from '../lib/api/history';
import { getJwt } from '../lib/auth';

/**
 * Phase 4.8 — "My filtered menus" history (mobile).
 *
 * Authenticated. Bounces to /login if the keychain has no JWT or
 * the API returns 401.
 */
export default function HistoryScreen() {
  const [visits, setVisits] = useState<HistoryVisit[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const jwt = await getJwt();
      if (!jwt) {
        router.replace('/login?next=%2Fhistory');
        return;
      }
      try {
        const res = await fetchHistory(jwt);
        if (cancelled) return;
        setVisits(res.visits);
        setTotal(res.total);
      } catch (e) {
        if (cancelled) return;
        if (e instanceof HistoryError && e.status === 401) {
          router.replace('/login?next=%2Fhistory');
          return;
        }
        setError((e as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (loading) {
    return (
      <View style={styles.center} testID="history-loading">
        <ActivityIndicator size="large" color={colors.bite} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.eyebrow}>My history</Text>
      <Text style={styles.headline}>Recent menus you've filtered</Text>
      <Text style={styles.summary}>
        {total === 0 ? "You haven't browsed any restaurants yet." : `${total} visit${total === 1 ? '' : 's'} on record.`}
      </Text>

      {error && <Text style={styles.error}>{error}</Text>}

      {visits.map((v) => (
        <VisitRow key={v.id} visit={v} />
      ))}
    </ScrollView>
  );
}

function VisitRow({ visit }: { visit: HistoryVisit }) {
  const when = new Date(visit.viewed_on).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
  return (
    <Pressable
      accessibilityLabel={`open-restaurant-${visit.restaurant.id}`}
      onPress={() =>
        router.push({
          pathname: '/restaurants/[id]',
          params: { id: visit.restaurant.id },
        })
      }
      style={styles.row}
      testID={`visit-${visit.id}`}
    >
      <Text style={styles.rowName}>{visit.restaurant.name}</Text>
      <Text style={styles.rowMeta}>
        {when} · {visit.restaurant.city.name}, {visit.restaurant.city.region}
      </Text>
      <Text style={styles.rowSummary}>
        Saw <Text style={styles.bold}>{visit.items_visible_count}</Text> item
        {visit.items_visible_count === 1 ? '' : 's'}
        {visit.items_hidden_count > 0 ? `, hiding ${visit.items_hidden_count}.` : '.'}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  content: { paddingTop: 60, paddingHorizontal: space['6'], paddingBottom: space['12'], gap: space['3'] },
  center: {
    flex: 1,
    backgroundColor: colors.bg,
    alignItems: 'center',
    justifyContent: 'center',
    padding: space['6'],
  },
  eyebrow: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  headline: { fontSize: fontSize['2xl'], fontWeight: '700', color: colors.text },
  summary: { fontSize: fontSize.base, color: colors.text },
  error: {
    backgroundColor: colors.biteLight,
    color: colors.biteDark,
    padding: space['3'],
    borderRadius: 8,
    fontSize: fontSize.sm,
  },
  row: { paddingVertical: space['3'], borderBottomWidth: 1, borderBottomColor: colors.border },
  rowName: { fontSize: fontSize.lg, fontWeight: '700', color: colors.text },
  rowMeta: { marginTop: 2, fontSize: fontSize.sm, color: colors.textMuted },
  rowSummary: { marginTop: 4, fontSize: fontSize.sm, color: colors.text },
  bold: { fontWeight: '700' },
});
