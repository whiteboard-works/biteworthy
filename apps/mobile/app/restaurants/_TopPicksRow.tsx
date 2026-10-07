import { useState } from 'react';
import { Image } from 'expo-image';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { colors, fontSize, radius, space } from '@biteworthy/ui-tokens';
import { tasteReasonLine, topPicksFromScores } from '@biteworthy/filter-engine';
import type { RestaurantItem } from '../../lib/api/restaurants';

/**
 * Phase 8.4 — mobile twin of the web Top Picks row (Phase 8.3).
 *
 * Renders from the SERVER's taste_score/taste_reasons via
 * filter-engine's shared `topPicksFromScores` — same thresholds (top
 * 5 visible score > 0, nothing under 3 positive picks).
 *
 * Matches the web row's layout and empty states: signed-out visitors
 * are pointed at sign-in (and brought back here after), signed-in
 * users with no taste signals at all are pointed at rating dishes, and
 * anyone partway there gets a quiet nudge.
 *
 * Copy rule: taste ≠ safety. The picks are "most likely to enjoy";
 * nothing here may imply a low-scored item is unsafe.
 */
const CARD_WIDTH = 176;

function EmptyState({
  items,
  restaurantId,
  signedIn,
}: {
  items: RestaurantItem[];
  restaurantId: string;
  signedIn: boolean;
}) {
  if (!signedIn) {
    return (
      <Pressable
        style={styles.banner}
        testID="top-picks-signed-out"
        accessibilityRole="link"
        accessibilityLabel="Sign in to see your best bets here"
        // replace, not push: login replaces itself with `next`, so a push
        // would leave this signed-out screen underneath for Back to reveal.
        onPress={() =>
          router.replace(`/login?next=${encodeURIComponent(`/restaurants/${restaurantId}`)}`)
        }
      >
        <Text style={styles.bannerText}>
          <Text style={styles.bannerLink}>Sign in</Text> and save a few dishes you like to see your
          best bets here.
        </Text>
      </Pressable>
    );
  }

  const hasAnyScore = items.some((i) => typeof i.taste_score === 'number');
  if (!hasAnyScore) {
    return (
      <View style={styles.banner} testID="top-picks-no-signals">
        <Text style={styles.bannerText}>
          Save or rate dishes you like and we’ll pick your best bets.
        </Text>
      </View>
    );
  }

  // Some taste signal, just not enough positive scores yet to clear
  // the 3-pick threshold — a quiet nudge, not a full banner.
  return (
    <Text style={styles.almost} testID="top-picks-almost">
      Rate a couple more dishes you like and we’ll surface your best bets here.
    </Text>
  );
}

export function TopPicksRow({
  items,
  restaurantId,
  signedIn,
}: {
  items: RestaurantItem[];
  /** Where sign-in should bring the visitor back to. */
  restaurantId: string;
  /** Picks which empty-state message applies — see EmptyState above. */
  signedIn: boolean;
}) {
  const [whyOpen, setWhyOpen] = useState(false);
  const picks = topPicksFromScores(items);
  if (picks.length === 0) {
    return <EmptyState items={items} restaurantId={restaurantId} signedIn={signedIn} />;
  }
  // Same rule as web: a tile only where it lines the strip up, so a
  // strip with no photos at all keeps its compact cards.
  const placeholders = picks.some((p) => p.photo_url);

  return (
    <View style={styles.wrap} testID="top-picks">
      <Text style={styles.heading}>Your best bets here</Text>
      <View style={styles.linkRow}>
        <Pressable
          testID="why-these"
          accessibilityRole="button"
          onPress={() => setWhyOpen((v) => !v)}
          hitSlop={8}
          style={styles.link}
        >
          <Text style={styles.linkText}>Why these?</Text>
        </Pressable>
        <Pressable
          testID="improve-picks"
          accessibilityRole="button"
          onPress={() => router.push('/onboarding?step=taste')}
          hitSlop={8}
          style={[styles.link, styles.improveLink]}
        >
          <Text style={styles.linkText}>Improve my picks</Text>
        </Pressable>
      </View>
      {whyOpen && (
        <Text style={styles.explainer} testID="why-these-explainer">
          Ranked from the tags and ingredients you said you love in your taste profile. Everything
          below passed your dietary filter too — these are just the dishes you’re most likely to
          enjoy.
        </Text>
      )}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        snapToInterval={CARD_WIDTH + space['3']}
        decelerationRate="fast"
        style={styles.stripScroller}
        contentContainerStyle={styles.strip}
      >
        {picks.map((item) => {
          const reason = tasteReasonLine(item.taste_reasons);
          return (
            <Pressable
              key={item.id}
              testID={`top-pick-${item.id}`}
              accessibilityRole="button"
              onPress={() => router.push(`/items/${item.id}`)}
              style={styles.card}
            >
              {item.photo_url ? (
                <Image source={{ uri: item.photo_url }} style={styles.photo} />
              ) : placeholders ? (
                <View
                  style={styles.photo}
                  testID={`pick-photo-placeholder-${item.id}`}
                  accessibilityElementsHidden
                  importantForAccessibility="no-hide-descendants"
                />
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
    padding: space['4'],
    borderWidth: 2,
    borderColor: colors.bite,
    borderRadius: radius.lg,
    // Web: bg-bite-light/50.
    backgroundColor: `${colors.biteLight}80`,
  },
  heading: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.biteDark,
  },
  linkRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    columnGap: space['4'],
    marginTop: space['1'],
  },
  link: {
    paddingVertical: space['1'],
  },
  improveLink: {
    marginLeft: 'auto',
  },
  linkText: {
    color: colors.bite,
    fontSize: fontSize.xs,
    fontWeight: '600',
  },
  explainer: {
    marginTop: space['2'],
    color: colors.biteDark,
    fontSize: fontSize.sm,
  },
  // Bleeds to the box edge so cards scroll out past the padding
  // instead of being clipped inside it.
  stripScroller: {
    marginTop: space['4'],
    marginHorizontal: -space['4'],
  },
  strip: {
    gap: space['3'],
    paddingHorizontal: space['4'],
    paddingBottom: space['1'],
  },
  card: {
    width: CARD_WIDTH,
    backgroundColor: colors.bg,
    borderWidth: 1,
    borderColor: `${colors.bite}66`,
    borderRadius: radius.lg,
    padding: space['3'],
    gap: space['1'],
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 2,
    shadowOffset: { width: 0, height: 1 },
    elevation: 1,
  },
  photo: {
    height: 96,
    width: '100%',
    borderRadius: radius.md,
    backgroundColor: colors.bgAlt,
    marginBottom: space['1'],
  },
  name: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.text,
  },
  reason: {
    fontSize: fontSize.xs,
    fontWeight: '600',
    color: colors.biteDark,
  },
  banner: {
    marginTop: space['4'],
    borderRadius: radius.md,
    backgroundColor: colors.biteLight,
    paddingHorizontal: space['3'],
    paddingVertical: space['2'],
  },
  bannerText: {
    fontSize: fontSize.sm,
    color: colors.biteDark,
  },
  bannerLink: {
    fontWeight: '600',
    textDecorationLine: 'underline',
  },
  almost: {
    marginTop: space['4'],
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
});
