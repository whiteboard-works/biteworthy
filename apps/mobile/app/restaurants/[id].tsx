import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  applyOverrides,
  groupItemsBySection,
  hiddenReasonLabel,
  type HideReason,
  type ItemSection,
} from '@biteworthy/filter-engine';
import { buildShareUrl } from '../../lib/share-url';
import { getJwt } from '../../lib/auth';
import {
  clearNeverHide,
  fetchRestaurant,
  fetchRestaurantItems,
  setNeverHide,
  type FilterSummary,
  type Restaurant,
  type RestaurantItem,
} from '../../lib/api/restaurants';
import { ItemRow } from './_ItemRow';
import { useTracker } from '../../lib/tracker-context';

/**
 * Phase 3.3 + 3.4 + 3.5 — filtered restaurant page with transparency
 * chips, a session-only override, and a strictness toggle.
 *
 * Each hidden item renders one <HiddenReasonChip> per reason
 * (e.g. "Contains dairy (Cheese)") and a "Show anyway" pressable that
 * flips it to visible client-side only.
 *
 * The strictness toggle in the header sends `?strictness=…` on the
 * next items refetch — the underlying user profile is unchanged. The
 * override applies for this session only, the same way "show anyway"
 * does. Phase 4 introduces a persistent profile-level toggle.
 */

type Strictness = 'relaxed' | 'balanced' | 'strict';
const STRICTNESSES: Strictness[] = ['relaxed', 'balanced', 'strict'];

export default function RestaurantScreen() {
  const tracker = useTracker();
  const params = useLocalSearchParams<{ id: string }>();
  const id = String(params.id ?? '');
  // Phase 5.8 — fire restaurant_tap once per id mount; the from
  // value defaults to 'direct' since mobile lists currently don't
  // pass a source param. Funnel queries can grow more granularity
  // later by adding `from` to the navigation links.
  const tapFiredRef = useRef(false);
  // Phase 4.1: pull the JWT from the keychain on mount; if absent
  // the page still loads (anonymous browse), but personalized filter
  // results require a sign-in.
  const [jwt, setJwt] = useState<string | undefined>(undefined);
  useEffect(() => {
    let cancelled = false;
    getJwt().then((t) => {
      if (!cancelled) setJwt(t ?? undefined);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const [restaurant, setRestaurant] = useState<Restaurant | null>(null);
  const [filter, setFilter] = useState<FilterSummary | null>(null);
  const [sections, setSections] = useState<ItemSection<RestaurantItem>[]>([]);
  const [loadingRestaurant, setLoadingRestaurant] = useState(true);
  const [loadingItems, setLoadingItems] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [shownAnyway, setShownAnyway] = useState<Set<string>>(() => new Set());
  // null = let the server pick (user profile or 'balanced'). Set by
  // the toggle when the user wants to override for this session.
  const [strictnessOverride, setStrictnessOverride] = useState<Strictness | null>(null);

  // Load the restaurant header once per id. Toggling strictness later
  // shouldn't re-fetch this — the header doesn't depend on it.
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setLoadingRestaurant(true);
    fetchRestaurant(id)
      .then((r) => {
        if (!cancelled) setRestaurant(r);
      })
      .catch((e) => {
        if (!cancelled) setError((e as Error).message);
      })
      .finally(() => {
        if (!cancelled) setLoadingRestaurant(false);
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  // Refetch items whenever id, jwt, or the strictness override change.
  // Reset the per-item "show anyway" set so refetching clears stale
  // overrides too (otherwise a swapped-out item id could still appear
  // visible when the new payload says it isn't there).
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setLoadingItems(true);
    setShownAnyway(new Set());

    fetchRestaurantItems(id, { jwt, strictness: strictnessOverride ?? undefined })
      .then((res) => {
        if (cancelled) return;
        setFilter(res.filter);
        setSections(groupItemsBySection(res.items));
        const totalVisible = res.items.filter((it) => it.status === 'visible').length;
        tracker.track('menu_filtered', {
          restaurant_slug: id,
          visible_count: totalVisible,
          hidden_count: res.items.length - totalVisible,
          filter_source: res.filter.source,
        });
        if (!tapFiredRef.current) {
          tapFiredRef.current = true;
          tracker.track('restaurant_tap', { restaurant_slug: id, from: 'direct' });
        }
      })
      .catch((e) => {
        if (!cancelled) setError((e as Error).message);
      })
      .finally(() => {
        if (!cancelled) setLoadingItems(false);
      });

    return () => {
      cancelled = true;
    };
  }, [id, jwt, strictnessOverride]);

  const toggleOverride = (itemId: string) => {
    setShownAnyway((prev) => {
      const next = new Set(prev);
      if (next.has(itemId)) next.delete(itemId);
      else next.add(itemId);
      return next;
    });
  };

  // Phase 4.2 — flip an item's persistent override server-side and
  // patch local state so the chip updates without a full refetch.
  // No-op without a JWT — the screen falls back to session overrides.
  const setPersistentOverride = async (itemId: string, next: boolean) => {
    if (!jwt) return;
    try {
      if (next) await setNeverHide(itemId, jwt);
      else await clearNeverHide(itemId, jwt);
    } catch (e) {
      setError((e as Error).message);
      return;
    }
    setSections((prev) =>
      prev.map((section) => ({
        ...section,
        visible: section.visible.map((it) =>
          it.id === itemId ? { ...it, overridden_by_user: next } : it,
        ),
        hidden: section.hidden.map((it) =>
          it.id === itemId ? { ...it, overridden_by_user: next } : it,
        ),
      })),
    );
  };

  const overriddenSections = useMemo(
    () => applyOverrides(sections, shownAnyway),
    [sections, shownAnyway],
  );

  if (!id) {
    return <CenteredMessage text="Missing restaurant id." />;
  }
  // First-time load: wait for both before showing the page.
  if ((loadingRestaurant || loadingItems) && (!restaurant || !filter)) {
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
      <StrictnessToggle
        active={strictnessOverride ?? filter.strictness}
        loading={loadingItems}
        onChange={(next) => {
          tracker.track('filter_changed', {
            kind: 'strictness',
            from: strictnessOverride ?? filter.strictness,
            to: next,
          });
          setStrictnessOverride(next);
        }}
      />
      <ShareLinkButton slug={restaurant.slug} filter={filter} />

      {overriddenSections.map((section) => (
        <SectionBlock
          key={section.id ?? '__none__'}
          section={section}
          restaurantSlug={restaurant.slug}
          shownAnyway={shownAnyway}
          onToggleOverride={toggleOverride}
          onSetPersistentOverride={setPersistentOverride}
          allowPersistent={!!jwt}
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

export function StrictnessToggle({
  active,
  loading,
  onChange,
}: {
  active: Strictness;
  loading: boolean;
  onChange: (next: Strictness) => void;
}) {
  return (
    <View style={styles.strictnessRow} testID="strictness-toggle">
      {STRICTNESSES.map((s) => {
        const selected = s === active;
        return (
          <Pressable
            key={s}
            accessibilityLabel={`strictness-${s}`}
            accessibilityState={{ selected, disabled: loading }}
            onPress={() => {
              if (!loading && !selected) onChange(s);
            }}
            style={[styles.strictnessChip, selected && styles.strictnessChipSelected]}
          >
            <Text
              style={[
                styles.strictnessText,
                selected && styles.strictnessTextSelected,
              ]}
            >
              {capitalize(s)}
            </Text>
          </Pressable>
        );
      })}
      {loading && (
        <ActivityIndicator
          size="small"
          color={colors.bite}
          style={styles.strictnessSpinner}
          testID="strictness-spinner"
        />
      )}
    </View>
  );
}

function ShareLinkButton({ slug, filter }: { slug: string; filter: FilterSummary }) {
  const tracker = useTracker();
  const handlePress = async () => {
    const url = buildShareUrl(slug, filter);
    await Share.share({ message: url, url });
    tracker.track('share_link_copied', { restaurant_slug: slug, via: 'native_share' });
  };
  return (
    <Pressable
      accessibilityLabel="share-link"
      onPress={handlePress}
      style={styles.shareButton}
    >
      <Text style={styles.shareText}>🔗 Share filter</Text>
    </Pressable>
  );
}

function capitalize(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function SectionBlock({
  section,
  restaurantSlug,
  shownAnyway,
  onToggleOverride,
  onSetPersistentOverride,
  allowPersistent,
}: {
  section: ItemSection<RestaurantItem>;
  restaurantSlug?: string;
  shownAnyway: Set<string>;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
  allowPersistent: boolean;
}) {
  const [hiddenOpen, setHiddenOpen] = useState(false);
  return (
    <View style={styles.section}>
      <Text style={styles.sectionName}>{section.name}</Text>

      {section.visible.map((item) => (
        <ItemRow
          key={item.id}
          item={item}
          restaurantSlug={restaurantSlug}
          overridden={shownAnyway.has(item.id) || item.overridden_by_user === true}
          onToggleOverride={onToggleOverride}
          onSetPersistentOverride={onSetPersistentOverride}
          allowPersistent={allowPersistent}
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
            restaurantSlug={restaurantSlug}
            hidden
            overridden={false}
            onToggleOverride={onToggleOverride}
            onSetPersistentOverride={onSetPersistentOverride}
            allowPersistent={allowPersistent}
          />
        ))}
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
  strictnessRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space['2'],
    marginTop: space['1'],
  },
  strictnessChip: {
    paddingHorizontal: space['3'],
    paddingVertical: space['1'],
    borderRadius: 999,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgAlt,
  },
  strictnessChipSelected: {
    borderColor: colors.bite,
    backgroundColor: colors.biteLight,
  },
  strictnessText: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  strictnessTextSelected: {
    color: colors.biteDark,
  },
  strictnessSpinner: {
    marginLeft: space['1'],
  },
  shareButton: {
    alignSelf: 'flex-start',
    paddingHorizontal: space['3'],
    paddingVertical: space['1'],
    borderRadius: 999,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgAlt,
  },
  shareText: {
    color: colors.text,
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
  hiddenToggle: {
    paddingVertical: space['2'],
  },
  hiddenToggleText: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
});
