import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { CURRENT_VERSION } from '@biteworthy/version-history';
import { searchRestaurants, type RestaurantSummary } from '../lib/api/restaurants';

/**
 * Phase 7.2 — the real home screen. Search published restaurants
 * (server-side ILIKE via ?q=), tap a row to open its filtered menu,
 * or jump straight into the scan flow when the place isn't listed
 * yet. "Near me" sorting is deferred — it needs expo-location and a
 * permissions pass; the API already returns lat/lng for it.
 */

const SEARCH_DEBOUNCE_MS = 300;

export default function Home() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<RestaurantSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(false);
    const timer = setTimeout(
      () => {
        searchRestaurants(query)
          .then((restaurants) => {
            if (cancelled) return;
            setResults(restaurants);
            setLoading(false);
          })
          .catch(() => {
            if (cancelled) return;
            setError(true);
            setLoading(false);
          });
      },
      // No debounce for the initial unfiltered load — only for typing.
      query ? SEARCH_DEBOUNCE_MS : 0,
    );
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query]);

  const meta = (r: RestaurantSummary) => {
    const place = `${r.city.name}, ${r.city.region}`;
    return r.street ? `${r.street} · ${place}` : place;
  };

  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>BiteWorthy</Text>
      <Text style={styles.headline}>Where are you eating?</Text>

      <TextInput
        accessibilityLabel="restaurant-search"
        placeholder="Search restaurants…"
        value={query}
        onChangeText={setQuery}
        autoCapitalize="none"
        autoCorrect={false}
        style={styles.input}
      />

      {loading ? (
        <ActivityIndicator accessibilityLabel="search-loading" color={colors.bite} />
      ) : error ? (
        <Text style={styles.error}>Couldn’t load restaurants. Pull to retry or check your connection.</Text>
      ) : (
        <FlatList
          data={results}
          keyExtractor={(r) => r.id}
          style={styles.list}
          renderItem={({ item }) => (
            <Pressable
              accessibilityLabel={`restaurant-${item.slug}`}
              onPress={() => router.push(`/restaurants/${item.id}?from=search`)}
              style={styles.row}
            >
              <Text style={styles.rowName}>{item.name}</Text>
              <Text style={styles.rowMeta}>{meta(item)}</Text>
            </Pressable>
          )}
          ListEmptyComponent={
            <View>
              <Text style={styles.empty}>
                {query ? `No matches for “${query}”.` : 'No restaurants yet.'}
              </Text>
              {/* The scan path, where someone actually needs it: they
                  looked for a place and it is not here yet. */}
              <Pressable accessibilityLabel="scan-a-menu" onPress={() => router.push('/chat')}>
                <Text style={styles.profileLink}>Scan a menu →</Text>
              </Pressable>
            </View>
          }
        />
      )}

      <Pressable accessibilityLabel="chat-link" onPress={() => router.push('/chat')}>
        <Text style={styles.profileLink}>Ask about a menu, or add one</Text>
      </Pressable>
      <Pressable accessibilityLabel="profile-link" onPress={() => router.push('/onboarding')}>
        <Text style={styles.profileLink}>Dietary preferences</Text>
      </Pressable>
      <Pressable accessibilityLabel="account-link" onPress={() => router.push('/settings/account')}>
        <Text style={styles.profileLink}>Account</Text>
      </Pressable>
      <Text style={styles.version} testID="app-version">
        BiteWorthy v{CURRENT_VERSION}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 60,
    paddingHorizontal: space['6'],
    paddingBottom: space['6'],
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
  headline: {
    fontSize: fontSize['2xl'],
    fontWeight: '700',
    color: colors.text,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: space['3'],
    fontSize: fontSize.base,
    color: colors.text,
  },
  list: {
    flex: 1,
  },
  row: {
    paddingVertical: space['3'],
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  rowName: {
    fontSize: fontSize.base,
    fontWeight: '600',
    color: colors.text,
  },
  rowMeta: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    marginTop: 2,
  },
  empty: {
    color: colors.textMuted,
    fontSize: fontSize.base,
    paddingVertical: space['4'],
  },
  missCta: {
    gap: space['1'],
  },
  missCtaText: {
    color: colors.bite,
    fontWeight: '600',
    fontSize: fontSize.base,
  },
  error: {
    color: colors.textMuted,
    fontSize: fontSize.base,
    paddingVertical: space['4'],
  },
  primaryButton: {
    backgroundColor: colors.bite,
    paddingVertical: space['4'],
    borderRadius: 12,
    alignItems: 'center',
  },
  primaryButtonText: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.base,
  },
  profileLink: {
    color: colors.bite,
    fontWeight: '600',
    textDecorationLine: 'underline',
    fontSize: fontSize.sm,
    textAlign: 'center',
  },
  version: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    textAlign: 'center',
    marginTop: space['2'],
  },
});
