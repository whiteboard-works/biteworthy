import { useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  createRestaurant,
  type DuplicateCandidate,
} from '../../lib/api/restaurants';
import { friendlyScanError } from '../../lib/api/ingestion-runs';

/**
 * Phase 6.6 — the "which restaurant?" step of the mobile scan flow
 * (twin of web's _NewRestaurantPicker). Creates a draft restaurant
 * with the Phase 6.2 dedup guard rendered as "did you mean…?" rows.
 *
 * City slug is a free input defaulting to the launch market — there
 * is no cities index endpoint yet (Phase-0 stub route).
 */
export function RestaurantPicker({
  jwt,
  onPicked,
  initialName,
}: {
  jwt: string;
  onPicked: (restaurant: { id: string; name: string }) => void;
  /** Phase 7.3 — prefilled from the home search-miss query. */
  initialName?: string;
}) {
  const [name, setName] = useState(initialName ?? '');
  const [citySlug, setCitySlug] = useState('durango');
  const [street, setStreet] = useState('');
  const [candidates, setCandidates] = useState<DuplicateCandidate[] | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (force: boolean) => {
    setError(null);
    if (!name.trim()) {
      setError('Restaurant name is required.');
      return;
    }
    try {
      setSubmitting(true);
      const result = await createRestaurant({
        name: name.trim(),
        citySlug: citySlug.trim(),
        street: street.trim() || undefined,
        force,
        jwt,
      });
      if (result.kind === 'duplicates') {
        setCandidates(result.candidates);
        return;
      }
      setCandidates(null);
      onPicked({ id: result.restaurant.id, name: result.restaurant.name });
    } catch (e) {
      setError(friendlyScanError(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={styles.wrap}>
      <TextInput
        accessibilityLabel="new-restaurant-name"
        placeholder="Restaurant name (e.g. Maria's Tacos)"
        value={name}
        onChangeText={setName}
        style={styles.input}
      />
      <View style={styles.row}>
        <TextInput
          accessibilityLabel="new-restaurant-city"
          placeholder="City slug"
          value={citySlug}
          onChangeText={setCitySlug}
          autoCapitalize="none"
          style={[styles.input, styles.rowItem]}
        />
        <TextInput
          accessibilityLabel="new-restaurant-street"
          placeholder="Street (optional)"
          value={street}
          onChangeText={setStreet}
          style={[styles.input, styles.rowItem]}
        />
      </View>
      <Pressable
        accessibilityLabel="create-restaurant"
        onPress={() => void submit(false)}
        disabled={submitting}
        style={[styles.button, submitting && styles.disabled]}
      >
        <Text style={styles.buttonText}>{submitting ? 'Checking…' : 'Create restaurant'}</Text>
      </Pressable>

      {error && (
        <Text accessibilityRole="alert" style={styles.error}>
          {error}
        </Text>
      )}

      {candidates && candidates.length > 0 && (
        <View style={styles.candidates} accessibilityLabel="possible-duplicates">
          <Text style={styles.candidatesTitle}>Did you mean one of these?</Text>
          {candidates.map((c) => (
            <Pressable
              key={c.id}
              accessibilityLabel={`use-candidate-${c.slug}`}
              onPress={() => onPicked({ id: c.id, name: c.name })}
              style={styles.candidateRow}
            >
              <View style={{ flex: 1 }}>
                <Text style={styles.candidateName}>{c.name}</Text>
                <Text style={styles.candidateMeta}>
                  {c.street ?? 'No address on file'} · {c.status}
                </Text>
              </View>
              <Text style={styles.candidateUse}>Use this</Text>
            </Pressable>
          ))}
          <Pressable
            accessibilityLabel="create-anyway"
            onPress={() => void submit(true)}
            disabled={submitting}
          >
            <Text style={styles.createAnyway}>None of these — create “{name}” anyway</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: space['3'] },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: space['3'],
    fontSize: fontSize.base,
    color: colors.text,
  },
  row: { flexDirection: 'row', gap: space['3'] },
  rowItem: { flex: 1 },
  button: {
    backgroundColor: colors.bite,
    paddingVertical: space['3'],
    borderRadius: 12,
    alignItems: 'center',
  },
  buttonText: { color: colors.bg, fontWeight: '700', fontSize: fontSize.base },
  disabled: { opacity: 0.5 },
  error: { color: '#c0392b', fontSize: fontSize.sm },
  candidates: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: space['3'],
    gap: space['3'],
    backgroundColor: colors.bgAlt,
  },
  candidatesTitle: { fontWeight: '700', color: colors.text, fontSize: fontSize.base },
  candidateRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space['3'],
    paddingVertical: space['2'],
  },
  candidateName: { fontWeight: '600', color: colors.text },
  candidateMeta: { color: colors.textMuted, fontSize: fontSize.sm },
  candidateUse: { color: colors.bite, fontWeight: '700' },
  createAnyway: {
    color: colors.text,
    textDecorationLine: 'underline',
    fontSize: fontSize.sm,
  },
});
