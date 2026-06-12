import { useEffect, useState } from 'react';
import {
  Alert,
  FlatList,
  Image,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  friendlyScanError,
  uploadIngestionRun,
  IngestionUploadError,
  type CapturedPage,
} from '../../lib/api/ingestion-runs';
import { getJwt } from '../../lib/auth';
import { RestaurantPicker } from './_RestaurantPicker';

/**
 * Phase 2.6 — multi-page menu capture.
 * Phase 6.6 — community scan flow: pick or create the restaurant
 * (Phase 6.2 dedup as "did you mean…?" rows), capture pages, upload,
 * then land on the swipe-verify screen (Phase 2.7) for your own run
 * (Phase 6.3 self-verify). Guardrail errors (Phase 6.1) render as
 * human copy via friendlyScanError.
 */
export default function IngestScreen() {
  const [restaurant, setRestaurant] = useState<{ id: string; name: string } | null>(null);
  const [manualId, setManualId] = useState('');
  const [jwt, setJwt] = useState<string | null>(null);
  const [pages, setPages] = useState<CapturedPage[]>([]);
  const [cameraOpen, setCameraOpen] = useState(false);
  const [permission, requestPermission] = useCameraPermissions();
  const [uploading, setUploading] = useState(false);

  const restaurantId = restaurant?.id ?? manualId;

  useEffect(() => {
    void getJwt().then((token) => {
      if (token) setJwt(token);
      else router.replace('/login?next=%2Fingest');
    });
  }, []);

  const onCapture = (uri: string) => {
    setPages((prev) => [...prev, { uri, mimeType: 'image/jpeg' }]);
    setCameraOpen(false);
  };

  const onDelete = (i: number) => {
    setPages((prev) => prev.filter((_, idx) => idx !== i));
  };

  const onUpload = async () => {
    if (!restaurantId || pages.length === 0) {
      Alert.alert('Missing info', 'Pick a restaurant and capture at least one page.');
      return;
    }
    if (!jwt) {
      router.replace('/login?next=%2Fingest');
      return;
    }
    try {
      setUploading(true);
      const run = await uploadIngestionRun({ restaurantId, pages, jwt });
      setPages([]);
      // Phase 6.6 — straight into swipe-verify for your own run.
      router.push(`/ingest/verify?runId=${run.id}`);
    } catch (e) {
      if (e instanceof IngestionUploadError && e.status === 401) {
        router.replace('/login?next=%2Fingest');
        return;
      }
      Alert.alert('Upload failed', friendlyScanError(e));
    } finally {
      setUploading(false);
    }
  };

  if (cameraOpen) {
    if (!permission) return <View testID="camera-permission-loading" />;
    if (!permission.granted) {
      return (
        <View style={styles.container}>
          <Text style={styles.headline}>Camera permission needed</Text>
          <Pressable onPress={requestPermission} style={styles.primaryButton}>
            <Text style={styles.primaryButtonText}>Grant access</Text>
          </Pressable>
        </View>
      );
    }
    return (
      <View style={{ flex: 1 }}>
        <CameraView
          style={{ flex: 1 }}
          facing="back"
          onCameraReady={() => {}}
          // The actual capture is wired in via a ref in production —
          // this skeleton shows the structure; fine-grained capture
          // gestures land alongside the real on-device testing pass.
        />
        <Pressable
          accessibilityLabel="capture-page"
          style={styles.captureButton}
          onPress={() => onCapture(`file:///mock/page-${pages.length + 1}.jpg`)}
        >
          <Text style={styles.captureButtonText}>📸 Capture page</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>Scan a menu</Text>
      <Text style={styles.headline}>
        {restaurant ? `Scanning for ${restaurant.name}` : 'Which restaurant?'}
      </Text>

      {restaurant ? (
        <Pressable accessibilityLabel="change-restaurant" onPress={() => setRestaurant(null)}>
          <Text style={styles.changeLink}>Change restaurant</Text>
        </Pressable>
      ) : (
        <>
          {jwt && <RestaurantPicker jwt={jwt} onPicked={setRestaurant} />}
          <TextInput
            accessibilityLabel="restaurant-id"
            placeholder="…or paste a restaurant UUID"
            value={manualId}
            onChangeText={setManualId}
            autoCapitalize="none"
            style={styles.input}
          />
        </>
      )}

      <FlatList
        data={pages}
        keyExtractor={(_, i) => `page-${i}`}
        horizontal
        contentContainerStyle={styles.thumbStrip}
        renderItem={({ item, index }) => (
          <Pressable accessibilityLabel={`page-thumb-${index}`} onLongPress={() => onDelete(index)}>
            <Image source={{ uri: item.uri }} style={styles.thumb} />
            <Text style={styles.thumbLabel}>Page {index + 1}</Text>
          </Pressable>
        )}
        ListEmptyComponent={<Text style={styles.empty}>No pages yet — tap Scan menu to start.</Text>}
      />

      <Pressable accessibilityLabel="open-camera" onPress={() => setCameraOpen(true)} style={styles.primaryButton}>
        <Text style={styles.primaryButtonText}>📷 Scan menu</Text>
      </Pressable>
      <Pressable
        accessibilityLabel="upload-all"
        onPress={onUpload}
        disabled={uploading || pages.length === 0}
        style={[styles.primaryButton, (uploading || pages.length === 0) && styles.disabled]}
      >
        <Text style={styles.primaryButtonText}>
          {uploading ? 'Uploading…' : `Upload ${pages.length} page${pages.length === 1 ? '' : 's'}`}
        </Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 60,
    paddingHorizontal: space['6'],
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
  thumbStrip: {
    gap: space['3'],
    paddingVertical: space['3'],
  },
  thumb: {
    width: 80,
    height: 80,
    borderRadius: 8,
    backgroundColor: colors.bgAlt,
  },
  thumbLabel: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginTop: 4,
    textAlign: 'center',
  },
  empty: {
    color: colors.textMuted,
    fontSize: fontSize.base,
    paddingVertical: space['4'],
  },
  changeLink: {
    color: colors.bite,
    fontWeight: '600',
    textDecorationLine: 'underline',
    fontSize: fontSize.sm,
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
  disabled: {
    opacity: 0.5,
  },
  captureButton: {
    position: 'absolute',
    bottom: 60,
    alignSelf: 'center',
    backgroundColor: colors.bite,
    paddingHorizontal: space['8'],
    paddingVertical: space['4'],
    borderRadius: 999,
  },
  captureButtonText: {
    color: colors.bg,
    fontWeight: '700',
  },
});
