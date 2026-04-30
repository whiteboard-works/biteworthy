import { useEffect, useMemo, useState } from 'react';
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
  type HideReason,
  type ItemSection,
  type Restaurant,
  type FilterSummary,
} from '../../lib/api/restaurants';
import { hiddenReasonLabel } from '../../lib/hidden-reason';
import { applyOverrides } from '../../lib/restaurant-overrides';

/**
 * Phase 3.3 + 3.4 — filtered restaurant page with transparency chips
 * and a session-only override.
 *
 * Each hidden item now renders one <HiddenReasonChip> per reason
 * (e.g. "Contains dairy (Cheese)"), and a "Show anyway" pressable
 * that flips the item to visible **client-side only** — no server
 * roundtrip, no profile mutation. The override resets when the
 * screen unmounts; Phase 4 introduces a persisted "never hide this
 * dish" override on UserProfile.
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
  const [shownAnyway, setShownAnyway] = useState<Set<string>>(() => new Set());

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    setShownAnyway(new Set());

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

  const toggleOverride = (itemId: string) => {
    setShownAnyway((prev) => {
      const next = new Set(prev);
      if (next.has(itemId)) next.delete(itemId);
      else next.add(itemId);
      return next;
    });
  };

  const overriddenSections = useMemo(
    () => applyOverrides(sections, shownAnyway),
    [sections, shownAnyway],
  );

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

  const totalHidden = overriddenSections.reduce((acc, s) => acc + s.hidden.length, 0);
  const totalVisible = overriddenSections.reduce((acc, s) => acc + s.visible.length, 0);

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

      {overriddenSections.map((section) => (
        <SectionBlock
          key={section.id ?? '__none__'}
          section={section}
          shownAnyway={shownAnyway}
          onToggleOverride={toggleOverride}
        />
      ))}

      {overriddenSections.length === 0 && (
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

function SectionBlock({
  section,
  shownAnyway,
  onToggleOverride,
}: {
  section: ItemSection;
  shownAnyway: Set<string>;
  onToggleOverride: (itemId: string) => void;
}) {
  const [hiddenOpen, setHiddenOpen] = useState(false);
  return (
    <View style={styles.section}>
      <Text style={styles.sectionName}>{section.name}</Text>

      {section.visible.map((item) => (
        <ItemRow
          key={item.id}
          item={item}
          overridden={shownAnyway.has(item.id)}
          onToggleOverride={onToggleOverride}
        />
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
        section.hidden.map((item) => (
          <ItemRow
            key={item.id}
            item={item}
            hidden
            overridden={false}
            onToggleOverride={onToggleOverride}
          />
        ))}
    </View>
  );
}

function ItemRow({
  item,
  hidden = false,
  overridden,
  onToggleOverride,
}: {
  item: FilteredItem;
  hidden?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
}) {
  // An item with reasons but rendered in the visible column means the
  // user tapped "show anyway" — keep the chips visible as a cue.
  const showChips = hidden || overridden;
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

      {showChips && item.reasons.length > 0 && (
        <View style={styles.chipRow}>
          {item.reasons.map((r, idx) => (
            <HiddenReasonChip key={idx} reason={r} />
          ))}
        </View>
      )}

      {item.reasons.length > 0 && (
        <Pressable
          accessibilityLabel={`toggle-override-${item.id}`}
          onPress={() => onToggleOverride(item.id)}
          style={styles.overrideButton}
        >
          <Text style={styles.overrideText}>
            {overridden ? 'Hide again' : 'Show anyway'}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

export function HiddenReasonChip({ reason }: { reason: HideReason }) {
  return (
    <View style={styles.chip} testID={`chip-${reason.kind}`}>
      <Text style={styles.chipText}>{hiddenReasonLabel(reason)}</Text>
    </View>
  );
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
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: space['1'],
    marginTop: space['2'],
  },
  chip: {
    paddingHorizontal: space['2'],
    paddingVertical: space['0_5'],
    borderRadius: 999,
    backgroundColor: colors.bgAlt,
    borderWidth: 1,
    borderColor: colors.border,
  },
  chipText: {
    fontSize: fontSize.xs,
    color: colors.hide,
    fontWeight: '600',
  },
  overrideButton: {
    marginTop: space['2'],
    paddingVertical: space['1'],
    alignSelf: 'flex-start',
  },
  overrideText: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
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
