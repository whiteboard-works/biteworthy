import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  fetchRestaurant,
  fetchRestaurantItems,
  groupItemsBySection,
  type FilteredItem,
  type ItemSection,
  type Restaurant,
  type FilterSummary,
} from '../../lib/api/restaurants';

/**
 * Phase 3.3 — filtered restaurant page.
 *
 *   1. Hits GET /api/v1/restaurants/:id for header info.
 *   2. Hits GET /api/v1/restaurants/:id/items (with optional JWT).
 *      Server applies the user's profile when authed (Phase 1.7).
 *   3. Renders sections + items; visible up top, hidden behind a
 *      "Items hidden by your filter (N)" expander per section.
 *
 * The transparency-chip translation + per-item override land in
 * Phase 3.4 — for now the screen labels hidden items with a generic
 * "Hidden" tag and lists their reasons by raw kind. Same JWT-pasted-
 * in-input workaround as the ingest/onboarding screens until Phase 4
 * brings expo-secure-store.
 */

export default function RestaurantScreen() {
  const params = useLocalSearchParams<{ id: string; jwt?: string }>();
  const id = String(params.id ?? '');
  const jwt = typeof params.jwt === 'string' ? params.jwt : undefined;

  const [restaurant, setRestaurant] = useState<Restaurant | null>(null);
  const [filter, setFilter] = useState<FilterSummary | null>(null);
  const [sections, setSections] = useState<ItemSection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setLoading(true);
    setError(null);

    Promise.all([fetchRestaurant(id), fetchRestaurantItems(id, { jwt })])
      .then(([r, itemsRes]) => {
        if (cancelled) return;
        setRestaurant(r);
        setFilter(itemsRes.filter);
        setSections(groupItemsBySection(itemsRes.items));
      })
      .catch((e) => {
        if (cancelled) return;
        setError((e as Error).message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [id, jwt]);

  if (!id) {
    return <CenteredMessage text="Missing restaurant id." />;
  }
  if (loading) {
    return (
      <View style={styles.center} testID="restaurant-loading">
        <ActivityIndicator size="large" color={colors.bite} />
      </View>
    );
  }
  if (error) {
    return <CenteredMessage text={`Could not load restaurant — ${error}`} />;
  }
  if (!restaurant || !filter) {
    return <CenteredMessage text="Restaurant not found." />;
  }

  const totalHidden = sections.reduce((acc, s) => acc + s.hidden.length, 0);
  const totalVisible = sections.reduce((acc, s) => acc + s.visible.length, 0);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.eyebrow}>{restaurant.city.name}, {restaurant.city.region}</Text>
      <Text style={styles.headline}>{restaurant.name}</Text>
      <Text style={styles.summary}>
        Showing <Text style={styles.bold}>{totalVisible}</Text> item
        {totalVisible === 1 ? '' : 's'} that match your filter
        {totalHidden > 0 ? `, hiding ${totalHidden}.` : '.'}
      </Text>
      <FilterBadge filter={filter} />

      {sections.map((section) => (
        <SectionBlock key={section.id ?? '__none__'} section={section} />
      ))}

      {sections.length === 0 && (
        <Text style={styles.empty}>No published items at this restaurant yet.</Text>
      )}
    </ScrollView>
  );
}

function FilterBadge({ filter }: { filter: FilterSummary }) {
  const label =
    filter.source === 'preset'
      ? `Preset · ${filter.preset_slug ?? 'unknown'}`
      : filter.source === 'user_profile'
      ? 'Your saved profile'
      : 'No filter';
  return (
    <View style={styles.filterBadge} testID="filter-badge">
      <Text style={styles.filterText}>
        {label} · {filter.strictness}
      </Text>
    </View>
  );
}

function SectionBlock({ section }: { section: ItemSection }) {
  const [hiddenOpen, setHiddenOpen] = useState(false);
  return (
    <View style={styles.section}>
      <Text style={styles.sectionName}>{section.name}</Text>

      {section.visible.map((item) => (
        <ItemRow key={item.id} item={item} />
      ))}

      {section.visible.length === 0 && section.hidden.length > 0 && (
        <Text style={styles.muted}>
          Every item in this section is hidden by your filter.
        </Text>
      )}

      {section.hidden.length > 0 && (
        <Pressable
          onPress={() => setHiddenOpen((v) => !v)}
          accessibilityLabel={`toggle-hidden-${section.id ?? 'none'}`}
          style={styles.hiddenToggle}
        >
          <Text style={styles.hiddenToggleText}>
            {hiddenOpen ? '▾ Hide' : '▸ Show'} items hidden by your filter (
            {section.hidden.length})
          </Text>
        </Pressable>
      )}

      {hiddenOpen &&
        section.hidden.map((item) => <ItemRow key={item.id} item={item} hidden />)}
    </View>
  );
}

function ItemRow({ item, hidden = false }: { item: FilteredItem; hidden?: boolean }) {
  return (
    <View
      style={[styles.itemRow, hidden && styles.itemRowHidden]}
      testID={`item-${item.id}`}
    >
      <Text style={[styles.itemName, hidden && styles.itemNameHidden]}>{item.name}</Text>
      {item.description ? (
        <Text style={[styles.itemDescription, hidden && styles.itemNameHidden]}>
          {item.description}
        </Text>
      ) : null}
      {hidden && (
        <View style={styles.reasonsBlock}>
          {item.reasons.map((r, idx) => (
            <Text key={idx} style={styles.reasonText}>
              {reasonLabel(r)}
            </Text>
          ))}
        </View>
      )}
    </View>
  );
}

function reasonLabel(r: FilteredItem['reasons'][number]): string {
  switch (r.kind) {
    case 'avoid_ingredient':
      return '• avoids ingredient';
    case 'avoid_tag':
      return '• avoids tag';
    case 'unconfirmed_strict':
      return `• not confirmed (${r.confidence}) — strict mode`;
  }
}

function CenteredMessage({ text }: { text: string }) {
  return (
    <View style={styles.center}>
      <Text style={styles.body}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  content: {
    paddingTop: 60,
    paddingHorizontal: space['6'],
    paddingBottom: space['12'],
    gap: space['3'],
  },
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
  headline: {
    fontSize: fontSize['2xl'],
    fontWeight: '700',
    color: colors.text,
  },
  summary: {
    fontSize: fontSize.base,
    color: colors.text,
  },
  bold: {
    fontWeight: '700',
  },
  body: {
    fontSize: fontSize.base,
    color: colors.text,
  },
  empty: {
    color: colors.textMuted,
    fontSize: fontSize.base,
    paddingVertical: space['6'],
    textAlign: 'center',
  },
  muted: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    paddingVertical: space['2'],
  },
  filterBadge: {
    alignSelf: 'flex-start',
    paddingHorizontal: space['3'],
    paddingVertical: space['1'],
    borderRadius: 999,
    backgroundColor: colors.biteLight,
  },
  filterText: {
    color: colors.biteDark,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  section: {
    marginTop: space['4'],
    gap: space['2'],
  },
  sectionName: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
  },
  itemRow: {
    paddingVertical: space['3'],
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  itemRowHidden: {
    opacity: 0.55,
  },
  itemName: {
    fontSize: fontSize.base,
    color: colors.text,
    fontWeight: '600',
  },
  itemNameHidden: {
    color: colors.hide,
  },
  itemDescription: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    marginTop: 2,
  },
  reasonsBlock: {
    marginTop: 4,
    gap: 2,
  },
  reasonText: {
    fontSize: fontSize.xs,
    color: colors.hide,
  },
  hiddenToggle: {
    paddingVertical: space['2'],
  },
  hiddenToggleText: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
});
