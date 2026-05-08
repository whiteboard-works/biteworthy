import { useEffect, useReducer, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  initialDraft,
  onboardingReducer,
  toProfilePayload,
  type DietaryPreset,
  type Strictness,
} from '@biteworthy/filter-engine';
import {
  fetchDietaryProfiles,
  saveProfile,
  searchIngredients,
  type IngredientSearchResult,
} from '../../lib/api/onboarding';
import { getJwt } from '../../lib/auth';
import { useTracker } from '../../lib/tracker-context';

/**
 * Phase 3.2 — 6-tap onboarding to a working dietary filter.
 *
 *   1. Pick presets ("What can't you eat?")
 *   2. Add specific ingredients ("Anything else?")
 *   3. Set strictness ("How strict?")
 *   4. Done → PATCH /api/v1/profile, navigate to /.
 *
 * Phase 4.1 dropped the paste-the-JWT field; auth comes from the
 * keychain-backed token stored by /login. A 401 means the session
 * expired — the user is bounced to /login?next=/onboarding.
 */
type Step = 'presets' | 'ingredients' | 'strictness' | 'done';

export default function OnboardingScreen() {
  const tracker = useTracker();
  const [step, setStep] = useState<Step>('presets');
  const [draft, dispatch] = useReducer(onboardingReducer, initialDraft);
  const [presets, setPresets] = useState<DietaryPreset[]>([]);
  const [loadingPresets, setLoadingPresets] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<IngredientSearchResult[]>([]);
  const [searchedIngredients, setSearchedIngredients] = useState<Map<string, IngredientSearchResult>>(new Map());
  const [saving, setSaving] = useState(false);

  // Load presets once.
  useEffect(() => {
    fetchDietaryProfiles()
      .then(setPresets)
      .catch((e) => Alert.alert('Could not load presets', (e as Error).message))
      .finally(() => setLoadingPresets(false));
  }, []);

  // Debounced ingredient search.
  useEffect(() => {
    if (step !== 'ingredients') return;
    const handle = setTimeout(() => {
      searchIngredients(searchQuery)
        .then((results) => {
          setSearchResults(results);
          setSearchedIngredients((prev) => {
            const next = new Map(prev);
            for (const r of results) next.set(r.id, r);
            return next;
          });
        })
        .catch(() => {
          // Search errors are non-fatal — silently no-op.
        });
    }, 250);
    return () => clearTimeout(handle);
  }, [searchQuery, step]);

  const finalize = async () => {
    const jwt = await getJwt();
    if (!jwt) {
      router.replace('/login?next=%2Fonboarding');
      return;
    }
    try {
      setSaving(true);
      const payload = toProfilePayload(draft, presets);
      await saveProfile(payload, jwt);
      tracker.track('profile_set', {
        preset_slug: draft.selectedPresetSlugs[0] ?? null,
        avoid_ingredient_count: payload.avoid_ingredient_ids.length,
        avoid_tag_count: payload.avoid_tag_ids.length,
        strictness: payload.strictness,
      });
      Alert.alert('Profile saved', 'Your dietary filter is ready.');
      router.replace('/');
    } catch (e) {
      const message = (e as Error).message;
      if (message.includes('401')) {
        router.replace('/login?next=%2Fonboarding');
        return;
      }
      Alert.alert('Save failed', message);
    } finally {
      setSaving(false);
    }
  };

  // ── Step bodies ──────────────────────────────────────────────────────
  if (step === 'presets') {
    return (
      <View style={styles.container}>
        <Text style={styles.eyebrow}>Step 1 of 4</Text>
        <Text style={styles.headline}>What can't you eat?</Text>
        <Text style={styles.body}>Tap any presets that apply. You can multi-select.</Text>

        {loadingPresets ? (
          <ActivityIndicator size="large" color={colors.bite} testID="presets-loading" />
        ) : (
          <ScrollView contentContainerStyle={styles.chipGrid}>
            {presets.map((p) => {
              const selected = draft.selectedPresetSlugs.includes(p.slug);
              return (
                <Pressable
                  key={p.slug}
                  accessibilityLabel={`preset-${p.slug}`}
                  onPress={() => dispatch({ type: 'TOGGLE_PRESET', slug: p.slug })}
                  style={[styles.chip, selected && styles.chipSelected]}
                >
                  <Text style={[styles.chipText, selected && styles.chipTextSelected]}>{p.name}</Text>
                  <Text style={[styles.chipDescription, selected && styles.chipTextSelected]}>{p.description}</Text>
                </Pressable>
              );
            })}
          </ScrollView>
        )}

        <Pressable accessibilityLabel="next-to-ingredients" onPress={() => setStep('ingredients')} style={styles.primary}>
          <Text style={styles.primaryText}>Next →</Text>
        </Pressable>
      </View>
    );
  }

  if (step === 'ingredients') {
    return (
      <View style={styles.container}>
        <Text style={styles.eyebrow}>Step 2 of 4</Text>
        <Text style={styles.headline}>Anything else?</Text>
        <Text style={styles.body}>Search for specific ingredients to avoid.</Text>

        <TextInput
          accessibilityLabel="ingredient-search"
          placeholder="Search ingredients (e.g. 'cilantro')"
          value={searchQuery}
          onChangeText={setSearchQuery}
          style={styles.input}
        />

        <FlatList
          data={searchResults}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => {
            const added = draft.manualIngredientIds.includes(item.id);
            return (
              <Pressable
                accessibilityLabel={`add-${item.slug}`}
                onPress={() =>
                  dispatch({
                    type: added ? 'REMOVE_MANUAL_INGREDIENT' : 'ADD_MANUAL_INGREDIENT',
                    ingredientId: item.id,
                  })
                }
                style={[styles.searchRow, added && styles.searchRowAdded]}
              >
                <View style={{ flex: 1 }}>
                  <Text style={styles.searchName}>{item.name}</Text>
                  {item.aliases.length > 0 && (
                    <Text style={styles.searchAliases}>aka {item.aliases.join(', ')}</Text>
                  )}
                </View>
                <Text style={[styles.addLabel, added && styles.addedLabel]}>{added ? '✓ added' : '+ add'}</Text>
              </Pressable>
            );
          }}
          ListEmptyComponent={
            searchQuery ? (
              <Text style={styles.empty}>No matches — try a different word.</Text>
            ) : (
              <Text style={styles.empty}>Type to search the ingredient catalog.</Text>
            )
          }
        />

        <Text style={styles.muted}>{draft.manualIngredientIds.length} added manually</Text>
        <Pressable accessibilityLabel="next-to-strictness" onPress={() => setStep('strictness')} style={styles.primary}>
          <Text style={styles.primaryText}>Next →</Text>
        </Pressable>
      </View>
    );
  }

  if (step === 'strictness') {
    return (
      <View style={styles.container}>
        <Text style={styles.eyebrow}>Step 3 of 4</Text>
        <Text style={styles.headline}>How strict?</Text>
        <Text style={styles.body}>
          Strict mode also hides items the AI hasn't fully confirmed. Pick balanced if unsure.
        </Text>

        {(['relaxed', 'balanced', 'strict'] as Strictness[]).map((s) => {
          const selected = draft.strictness === s;
          return (
            <Pressable
              key={s}
              accessibilityLabel={`strictness-${s}`}
              onPress={() => dispatch({ type: 'SET_STRICTNESS', strictness: s })}
              style={[styles.chip, selected && styles.chipSelected, { width: '100%' }]}
            >
              <Text style={[styles.chipText, selected && styles.chipTextSelected]}>
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </Text>
              <Text style={[styles.chipDescription, selected && styles.chipTextSelected]}>
                {s === 'relaxed' && 'Show items even if some ingredients are inferred.'}
                {s === 'balanced' && 'Hide items where the avoid match is confident.'}
                {s === 'strict'  && 'Also hide items the AI marked suggested or inferred.'}
              </Text>
            </Pressable>
          );
        })}

        <Pressable accessibilityLabel="next-to-done" onPress={() => setStep('done')} style={styles.primary}>
          <Text style={styles.primaryText}>Review →</Text>
        </Pressable>
      </View>
    );
  }

  // step === 'done'
  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>Step 4 of 4</Text>
      <Text style={styles.headline}>Ready?</Text>

      <Text style={styles.body}>
        Avoiding <Text style={{ fontWeight: '700' }}>
          {draft.selectedPresetSlugs.length} preset{draft.selectedPresetSlugs.length === 1 ? '' : 's'}
        </Text> + <Text style={{ fontWeight: '700' }}>
          {draft.manualIngredientIds.length} ingredient{draft.manualIngredientIds.length === 1 ? '' : 's'}
        </Text>, strictness <Text style={{ fontWeight: '700' }}>{draft.strictness}</Text>.
      </Text>

      <Pressable
        accessibilityLabel="finish"
        onPress={finalize}
        disabled={saving}
        style={[styles.primary, saving && { opacity: 0.5 }]}
      >
        <Text style={styles.primaryText}>{saving ? 'Saving…' : 'Save profile'}</Text>
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
  body: {
    fontSize: fontSize.base,
    color: colors.text,
  },
  muted: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
  },
  empty: {
    color: colors.textMuted,
    fontSize: fontSize.base,
    paddingVertical: space['6'],
    textAlign: 'center',
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: space['3'],
    fontSize: fontSize.base,
    color: colors.text,
  },
  chipGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: space['3'],
    paddingVertical: space['3'],
  },
  chip: {
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgAlt,
    borderRadius: 12,
    padding: space['3'],
    minWidth: '46%',
    flexGrow: 1,
  },
  chipSelected: {
    borderColor: colors.bite,
    backgroundColor: colors.biteLight,
  },
  chipText: {
    fontWeight: '700',
    fontSize: fontSize.base,
    color: colors.text,
  },
  chipTextSelected: {
    color: colors.biteDark,
  },
  chipDescription: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    marginTop: 4,
  },
  searchRow: {
    flexDirection: 'row',
    paddingVertical: space['3'],
    paddingHorizontal: space['3'],
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    alignItems: 'center',
  },
  searchRowAdded: {
    backgroundColor: colors.biteLight,
  },
  searchName: {
    fontSize: fontSize.base,
    color: colors.text,
  },
  searchAliases: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
  addLabel: {
    color: colors.bite,
    fontWeight: '600',
  },
  addedLabel: {
    color: colors.ok,
  },
  primary: {
    backgroundColor: colors.bite,
    paddingVertical: space['4'],
    borderRadius: 12,
    alignItems: 'center',
    marginTop: 'auto',
  },
  primaryText: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.base,
  },
});
