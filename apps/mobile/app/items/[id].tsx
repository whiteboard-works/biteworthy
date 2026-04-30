import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Image,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  createReview,
  fetchReviews,
  type ReviewPayload,
} from '../../lib/api/reviews';
import { getJwt } from '../../lib/auth';

/**
 * Phase 4.4 — item detail screen with reviews + write-a-review sheet.
 *
 * Linked from the restaurant page via the per-item "X reviews" badge.
 * Anonymous users see the review list; the write sheet bounces to
 * /login when no JWT is present in the keychain.
 *
 * Photo capture re-uses expo-image-picker rather than expo-camera so
 * the user can pick from the library OR open the camera; the Phase
 * 2.6 multi-page CameraView is overkill for a single review photo.
 */
type Params = {
  id: string;
  itemName?: string;
};

export default function ItemDetailScreen() {
  const params = useLocalSearchParams<Params>();
  const itemId = String(params.id ?? '');
  const headerName = typeof params.itemName === 'string' ? params.itemName : 'Item';

  const [reviews, setReviews] = useState<ReviewPayload[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [composerOpen, setComposerOpen] = useState(false);

  const reload = async () => {
    if (!itemId) return;
    try {
      setLoading(true);
      setError(null);
      const res = await fetchReviews(itemId);
      setReviews(res.reviews);
      setTotal(res.total);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [itemId]);

  const onWrite = async () => {
    const jwt = await getJwt();
    if (!jwt) {
      router.replace(`/login?next=${encodeURIComponent(`/items/${itemId}`)}`);
      return;
    }
    setComposerOpen(true);
  };

  if (!itemId) return <Center text="Missing item id." />;
  if (loading && reviews.length === 0) {
    return (
      <View style={styles.center} testID="item-loading">
        <ActivityIndicator size="large" color={colors.bite} />
      </View>
    );
  }
  if (error) return <Center text={`Could not load reviews — ${error}`} />;

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.eyebrow}>Item</Text>
        <Text style={styles.headline}>{headerName}</Text>
        <Text style={styles.summary}>
          <Text style={styles.bold}>
            {total} review{total === 1 ? '' : 's'}
          </Text>
        </Text>

        <Pressable accessibilityLabel="write-review" onPress={onWrite} style={styles.primary}>
          <Text style={styles.primaryText}>Write a review</Text>
        </Pressable>

        <FlatList
          data={reviews}
          scrollEnabled={false}
          keyExtractor={(r) => r.id}
          renderItem={({ item }) => <ReviewCard review={item} />}
          ListEmptyComponent={
            <Text style={styles.empty}>No reviews yet — be the first.</Text>
          }
        />
      </ScrollView>

      {composerOpen && (
        <ReviewComposer
          itemId={itemId}
          onCancel={() => setComposerOpen(false)}
          onSubmitted={(saved) => {
            setReviews((prev) => [saved, ...prev]);
            setTotal((n) => n + 1);
            setComposerOpen(false);
          }}
        />
      )}
    </View>
  );
}

function ReviewCard({ review }: { review: ReviewPayload }) {
  return (
    <View style={styles.reviewCard} testID={`review-${review.id}`}>
      <Text style={styles.reviewAuthor}>
        {review.user.display_name ?? review.user.handle ?? 'Diner'} ·{' '}
        <Text style={styles.reviewRating}>{'★'.repeat(review.rating)}{'☆'.repeat(5 - review.rating)}</Text>
      </Text>
      {review.body ? <Text style={styles.reviewBody}>{review.body}</Text> : null}
      {review.photo_url ? (
        <Image source={{ uri: review.photo_url }} style={styles.reviewPhoto} accessibilityLabel="review-photo" />
      ) : null}
    </View>
  );
}

function ReviewComposer({
  itemId,
  onCancel,
  onSubmitted,
}: {
  itemId: string;
  onCancel: () => void;
  onSubmitted: (saved: ReviewPayload) => void;
}) {
  const [rating, setRating] = useState(0);
  const [body, setBody] = useState('');
  const [photoUri, setPhotoUri] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const pickPhoto = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Photo permission needed', 'Enable photo access in Settings to attach a picture.');
      return;
    }
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.8,
    });
    if (!res.canceled && res.assets[0]) setPhotoUri(res.assets[0].uri);
  };

  const submit = async () => {
    if (rating < 1 || rating > 5) {
      Alert.alert('Pick a rating', 'Tap one of the stars first.');
      return;
    }
    const jwt = await getJwt();
    if (!jwt) {
      Alert.alert('Sign in needed', 'Your session expired — please sign in again.');
      return;
    }
    try {
      setSubmitting(true);
      const saved = await createReview(itemId, jwt, {
        rating,
        body: body.trim() || undefined,
        photoUri: photoUri ?? undefined,
      });
      onSubmitted(saved);
    } catch (e) {
      Alert.alert('Save failed', (e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={styles.composerSheet} testID="review-composer">
      <Text style={styles.composerTitle}>Write a review</Text>

      <View style={styles.starRow}>
        {[1, 2, 3, 4, 5].map((n) => (
          <Pressable
            key={n}
            accessibilityLabel={`star-${n}`}
            onPress={() => setRating(n)}
            style={styles.starTouch}
          >
            <Text style={[styles.star, rating >= n && styles.starOn]}>★</Text>
          </Pressable>
        ))}
      </View>

      <TextInput
        accessibilityLabel="review-body"
        placeholder="Optional notes — what was good, what wasn't"
        value={body}
        onChangeText={setBody}
        multiline
        style={styles.input}
      />

      <Pressable accessibilityLabel="pick-photo" onPress={pickPhoto} style={styles.secondary}>
        <Text style={styles.secondaryText}>{photoUri ? '✓ Photo attached — change' : '+ Add a photo (optional)'}</Text>
      </Pressable>

      <View style={styles.composerActions}>
        <Pressable accessibilityLabel="cancel-review" onPress={onCancel} style={styles.secondary}>
          <Text style={styles.secondaryText}>Cancel</Text>
        </Pressable>
        <Pressable
          accessibilityLabel="submit-review"
          onPress={submit}
          disabled={submitting}
          style={[styles.primary, submitting && { opacity: 0.5 }]}
        >
          <Text style={styles.primaryText}>{submitting ? 'Posting…' : 'Post review'}</Text>
        </Pressable>
      </View>
    </View>
  );
}

function Center({ text }: { text: string }) {
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
  primary: {
    backgroundColor: colors.bite,
    paddingVertical: space['4'],
    borderRadius: 12,
    alignItems: 'center',
  },
  primaryText: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.base,
  },
  secondary: {
    paddingVertical: space['3'],
    paddingHorizontal: space['4'],
    borderRadius: 8,
    backgroundColor: colors.bgAlt,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
  },
  secondaryText: {
    color: colors.text,
    fontWeight: '600',
    fontSize: fontSize.sm,
  },
  reviewCard: {
    marginTop: space['3'],
    paddingVertical: space['3'],
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  reviewAuthor: {
    fontSize: fontSize.sm,
    color: colors.text,
    fontWeight: '600',
  },
  reviewRating: {
    color: colors.bite,
    fontWeight: '700',
  },
  reviewBody: {
    fontSize: fontSize.base,
    color: colors.text,
    marginTop: 4,
  },
  reviewPhoto: {
    marginTop: space['2'],
    width: '100%',
    height: 200,
    borderRadius: 12,
    backgroundColor: colors.bgAlt,
  },
  composerSheet: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: colors.bg,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    paddingTop: space['4'],
    paddingHorizontal: space['6'],
    paddingBottom: space['8'],
    gap: space['3'],
  },
  composerTitle: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
  },
  starRow: {
    flexDirection: 'row',
    gap: space['2'],
    paddingVertical: space['1'],
  },
  starTouch: {
    paddingHorizontal: 4,
  },
  star: {
    fontSize: 36,
    color: colors.border,
  },
  starOn: {
    color: colors.bite,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: space['3'],
    fontSize: fontSize.base,
    color: colors.text,
    minHeight: 80,
    textAlignVertical: 'top',
  },
  composerActions: {
    flexDirection: 'row',
    gap: space['3'],
    justifyContent: 'flex-end',
  },
});
