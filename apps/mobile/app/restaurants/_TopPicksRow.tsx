import { useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { tasteReasonLine, topPicksFromScores } from '@biteworthy/filter-engine';
import type { RestaurantItem } from '../../lib/api/restaurants';

/**
 * Phase 8.4 — mobile twin of the web Top Picks row (Phase 8.3).
 *
 * Renders from the SERVER's taste_score/taste_reasons via
 * filter-engine's shared `topPicksFromScores` — same thresholds (top
 * 5 visible score > 0, nothing under 3 positive picks), same
 * anonymous behavior (null scores → renders nothing, screen
 * unchanged).
 *
 * Copy rule: taste ≠ safety. The picks are "most likely to enjoy";
 * nothing here may imply a low-scored item is unsafe.
 */
export function TopPicksRow({ items }: { items: RestaurantItem[] }) {
  const [whyOpen, setWhyOpen] = useState(false);
  const picks = topPicksFromScores(items);
  if (picks.length === 0) return null;

  return (
    <View style={styles.wrap} testID="top-picks">
      <View style={styles.headerRow}>
        <Text style={styles.heading}>Top picks for you</Text>
        <Pressable accessibilityLabel="why-these" onPress={() => setWhyOpen((v) => !v)}>
          <Text style={styles.whyLink}>Why these?</Text>
        </Pressable>
      </View>
      {whyOpen && (
        <Text style={styles.explainer} testID="why-these-explainer">
          Ranked from the tags and ingredients you said you love in your taste profile.
          Everything below passed your dietary filter too — these are just the dishes
          you’re most likely to enjoy.
        </Text>
      )}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.strip}>
        {picks.map((item) => {
          const reason = tasteReasonLine(item.taste_reasons);
          return (
            <Pressable
              key={item.id}
              accessibilityLabel={`top-pick-${item.id}`}
              onPress={() => router.push(`/items/${item.id}`)}
              style={styles.card}
            >
              {item.photo_url ? (
                <Image source={{ uri: item.photo_url }} style={styles.photo} />
              ) : null}
              <Text style={styles.name} numberOfLines={2}>
                {item.name}
              </Text>
              {reason && (
                <Text style={styles.reason} numberOfLines={2} testID={`pick-reason-${item.id}`}>
                  {reason}
                </Text>
              )}
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    marginTop: space['4'],
    gap: space['2'],
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: space['2'],
  },
  heading: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
  },
  whyLink: {
    color: colors.bite,
    fontSize: fontSize.xs,
    fontWeight: '600',
  },
  explainer: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
  },
  strip: {
    gap: space['3'],
  },
  card: {
    width: 160,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: space['2'],
    gap: space['1'],
  },
  photo: {
    height: 90,
    width: '100%',
    borderRadius: 8,
    backgroundColor: colors.bgAlt,
  },
  name: {
    fontSize: fontSize.sm,
    fontWeight: '600',
    color: colors.text,
  },
  reason: {
    fontSize: fontSize.xs,
    color: colors.biteDark,
  },
});
