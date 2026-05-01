import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Image } from 'expo-image';
import { router } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import type { RestaurantItem } from '../../lib/api/restaurants';
import { HiddenReasonChip } from './[id]';

/**
 * Phase 4.11.4 / post-5 — single menu-item row, extracted from
 * `[id].tsx` so render tests can target it directly. Mirrors the web
 * extraction in PR #190.
 *
 * The original Phase 4.11.4 PR (#169) deferred a render snapshot
 * for the dish-photo `<Image>` because the test infra wasn't wired
 * yet. PR #191 wired jest-expo + `@testing-library/react-native`;
 * this PR extracts ItemRow + ships the deferred snapshot.
 *
 * Behavior is byte-identical to the previous in-file version of
 * ItemRow — no logic changes, just a file boundary.
 *
 * The `_` prefix on the filename is the expo-router convention for
 * private files (excluded from routing).
 */
export interface ItemRowProps {
  item: RestaurantItem;
  hidden?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
  allowPersistent: boolean;
}

export function ItemRow({
  item,
  hidden = false,
  overridden,
  onToggleOverride,
  onSetPersistentOverride,
  allowPersistent,
}: ItemRowProps) {
  // An item with reasons but rendered in the visible column means the
  // user tapped "show anyway" — keep the chips visible as a cue.
  const showChips = hidden || overridden;
  const reviewsCount = item.reviews_count ?? 0;
  return (
    <View
      style={[styles.itemRow, hidden && styles.itemRowHidden]}
      testID={`item-${item.id}`}
    >
      {item.photo_url ? (
        // Phase 4.11.4 — cropped dish photo from the source menu page.
        // expo-image handles caching + progressive load better than
        // react-native's Image, and is already a dep.
        <Image
          source={{ uri: item.photo_url }}
          accessibilityLabel={`photo of ${item.name}`}
          testID={`item-photo-${item.id}`}
          contentFit="cover"
          style={styles.itemPhoto}
        />
      ) : null}
      <Text style={[styles.itemName, hidden && styles.itemNameHidden]}>{item.name}</Text>
      {item.description ? (
        <Text style={[styles.itemDescription, hidden && styles.itemNameHidden]}>
          {item.description}
        </Text>
      ) : null}

      <Pressable
        accessibilityLabel={`open-item-${item.id}`}
        onPress={() =>
          router.push({
            pathname: '/items/[id]',
            params: { id: item.id, itemName: item.name },
          })
        }
        style={styles.reviewBadge}
      >
        <Text style={styles.reviewBadgeText}>
          {reviewsCount === 0
            ? 'Be the first to review'
            : `${reviewsCount} review${reviewsCount === 1 ? '' : 's'} →`}
        </Text>
      </Pressable>

      {showChips && item.reasons.length > 0 && (
        <View style={styles.chipRow}>
          {item.reasons.map((r, idx) => (
            <HiddenReasonChip key={idx} reason={r} />
          ))}
        </View>
      )}

      {item.reasons.length > 0 && (
        <View style={styles.overrideRow}>
          {item.overridden_by_user ? (
            <Pressable
              accessibilityLabel={`undo-never-hide-${item.id}`}
              onPress={() => onSetPersistentOverride(item.id, false)}
              style={styles.overrideButton}
            >
              <Text style={styles.overrideText}>Always shown — undo</Text>
            </Pressable>
          ) : (
            <>
              <Pressable
                accessibilityLabel={`toggle-override-${item.id}`}
                onPress={() => onToggleOverride(item.id)}
                style={styles.overrideButton}
              >
                <Text style={styles.overrideText}>
                  {overridden ? 'Hide again' : 'Show anyway'}
                </Text>
              </Pressable>
              {overridden && allowPersistent && (
                <Pressable
                  accessibilityLabel={`set-never-hide-${item.id}`}
                  onPress={() => onSetPersistentOverride(item.id, true)}
                  style={styles.overrideButton}
                >
                  <Text style={styles.persistentOverrideText}>Never hide this dish</Text>
                </Pressable>
              )}
            </>
          )}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
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
  itemPhoto: {
    width: '100%',
    height: 180,
    borderRadius: 8,
    marginBottom: space['2'],
    backgroundColor: colors.bgAlt,
  },
  reviewBadge: {
    marginTop: space['1'],
    alignSelf: 'flex-start',
  },
  reviewBadgeText: {
    color: colors.bite,
    fontSize: fontSize.xs,
    fontWeight: '600',
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: space['1'],
    marginTop: space['2'],
  },
  overrideRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: space['3'],
    marginTop: space['1'],
  },
  overrideButton: {
    paddingVertical: space['1'],
    alignSelf: 'flex-start',
  },
  overrideText: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  persistentOverrideText: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
});
