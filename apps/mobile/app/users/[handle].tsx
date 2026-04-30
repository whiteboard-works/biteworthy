import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  fetchPublicUserProfile,
  type PublicUserProfile,
  type UserReview,
} from '../../lib/api/users';

/**
 * Phase 4.7 — public user profile screen (mobile mirror of /u/[handle]).
 * Anonymous endpoint; no auth required to view.
 */
export default function UserProfileScreen() {
  const params = useLocalSearchParams<{ handle: string }>();
  const handle = String(params.handle ?? '');

  const [profile, setProfile] = useState<PublicUserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!handle) return;
    let cancelled = false;
    setLoading(true);
    setNotFound(false);
    setError(null);
    fetchPublicUserProfile(handle)
      .then((p) => {
        if (cancelled) return;
        if (p === null) setNotFound(true);
        else setProfile(p);
      })
      .catch((e) => {
        if (!cancelled) setError((e as Error).message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [handle]);

  if (!handle) return <Center text="Missing handle." />;
  if (loading) return <CenterSpinner />;
  if (notFound) return <Center text={`No diner @${handle} found.`} />;
  if (error) return <Center text={`Could not load profile — ${error}`} />;
  if (!profile) return null;

  const memberSince = new Date(profile.member_since).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
  });

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.eyebrow}>Diner</Text>
      <Text style={styles.headline}>{profile.display_name ?? `@${profile.handle}`}</Text>
      <Text style={styles.muted}>@{profile.handle} · Member since {memberSince}</Text>

      <View style={styles.statsRow}>
        <Stat label="Reviews" value={profile.reviews_count} />
        <Stat label="Restaurants" value={profile.restaurants_reviewed_count} />
      </View>

      <Text style={styles.sectionTitle}>Recent reviews</Text>
      {profile.recent_reviews.length === 0 ? (
        <Text style={styles.empty}>No reviews yet.</Text>
      ) : (
        profile.recent_reviews.map((r) => <ReviewRow key={r.id} review={r} />)
      )}
    </ScrollView>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={styles.statValue}>{value}</Text>
    </View>
  );
}

function ReviewRow({ review }: { review: UserReview }) {
  return (
    <Pressable
      accessibilityLabel={`open-item-${review.item.id}`}
      onPress={() =>
        router.push({
          pathname: '/items/[id]',
          params: { id: review.item.id, itemName: review.item.name },
        })
      }
      style={styles.reviewRow}
      testID={`review-${review.id}`}
    >
      <Text style={styles.reviewMeta}>
        <Text style={styles.reviewStars}>{'★'.repeat(review.rating)}{'☆'.repeat(5 - review.rating)}</Text>
        {' on '}
        <Text style={styles.reviewItem}>{review.item.name}</Text>
        <Text style={styles.reviewWhere}> at {review.item.restaurant.name}</Text>
      </Text>
      {review.body ? <Text style={styles.reviewBody}>{review.body}</Text> : null}
      {review.photo_url ? (
        <Image source={{ uri: review.photo_url }} style={styles.reviewPhoto} accessibilityLabel="review-photo" />
      ) : null}
    </Pressable>
  );
}

function Center({ text }: { text: string }) {
  return (
    <View style={styles.center}>
      <Text style={styles.body}>{text}</Text>
    </View>
  );
}

function CenterSpinner() {
  return (
    <View style={styles.center} testID="profile-loading">
      <ActivityIndicator size="large" color={colors.bite} />
    </View>
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
  muted: { fontSize: fontSize.sm, color: colors.textMuted },
  body: { fontSize: fontSize.base, color: colors.text },
  empty: { color: colors.textMuted, fontSize: fontSize.base, paddingVertical: space['4'], textAlign: 'center' },
  statsRow: { flexDirection: 'row', gap: space['3'], marginTop: space['3'] },
  stat: {
    flex: 1,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: space['3'],
    paddingVertical: space['2'],
  },
  statLabel: { color: colors.textMuted, fontSize: fontSize.xs, textTransform: 'uppercase', letterSpacing: 1 },
  statValue: { color: colors.text, fontSize: fontSize.xl, fontWeight: '700', marginTop: 4 },
  sectionTitle: { fontSize: fontSize.lg, fontWeight: '700', color: colors.text, marginTop: space['4'] },
  reviewRow: { paddingVertical: space['3'], borderBottomWidth: 1, borderBottomColor: colors.border },
  reviewMeta: { fontSize: fontSize.sm, color: colors.text },
  reviewStars: { color: colors.bite, fontWeight: '700' },
  reviewItem: { fontWeight: '700', color: colors.text },
  reviewWhere: { color: colors.textMuted },
  reviewBody: { fontSize: fontSize.base, color: colors.text, marginTop: 4 },
  reviewPhoto: { marginTop: space['2'], width: '100%', height: 180, borderRadius: 12, backgroundColor: colors.bgAlt },
});
