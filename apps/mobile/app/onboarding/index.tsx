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
import { router, useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import {
  initialDraft,
  onboardingReducer,
  tasteStateOf,
  toProfilePayload,
  toTastePayload,
  type DietaryPreset,
  type Strictness,
} from '@biteworthy/filter-engine';
import {
  fetchDietaryProfiles,
  fetchTags,
  saveProfile,
  saveTaste,
  searchIngredients,
  type IngredientSearchResult,
  type TasteTag,
} from '../../lib/api/onboarding';
import { getJwt } from '../../lib/auth';
import { useTracker } from '../../lib/tracker-context';

/**
 * Phase 3.2 — 6-tap onboarding to a working dietary filter.
 *
 *   1. Pick presets ("What can't you eat?")
 *   2. Add specific ingredients ("Anything else?")
 *   3. Set strictness ("How strict?")
 *   4. Taste ("What do you love?") — Phase 8.5, skippable
 *   5. Done → PATCH /api/v1/profile, navigate to /.
 *
 * Phase 4.1 dropped the paste-the-JWT field; auth comes from the
 * keychain-backed token stored by /login. A 401 means the session
 * expired — the user is bounced to /login?next=/onboarding.
 *
 * Phase 8.5 — `?step=taste` enters the taste step standalone ("Improve
 * my picks"). That mode saves ONLY the taste arrays (toTastePayload),
 * so refining picks can never wipe the avoid lists. Safety filters,
 * taste ranks.
 */
type Step = 'presets' | 'ingredients' | 'strictness' | 'taste' | 'done';

export default function OnboardingScreen() {
  const tracker = useTracker();
  const params = useLocalSearchParams<{ step?: string }>();
  const standalone = params.step === 'taste';
  const [step, setStep] = useState<Step>(standalone ? 'taste' : 'presets');
  const [draft, dispatch] = useReducer(onboardingReducer, initialDraft);
  const [presets, setPresets] = useState<DietaryPreset[]>([]);
  const [loadingPresets, setLoadingPresets] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<IngredientSearchResult[]>([]);
  const [searchedIngredients, setSearchedIngredients] = useState<Map<string, IngredientSearchResult>>(new Map());
  const [tags, setTags] = useState<TasteTag[]>([]);
  const [tasteQuery, setTasteQuery] = useState('');
  const [tasteResults, setTasteResults] = useState<IngredientSearchResult[]>([]);
  const [saving, setSaving] = useState(false);
  // Legal remediation E1 — the user must accept the allergen disclaimer
  // before the profile saves; the acceptance is recorded server-side.
  const [acknowledged, setAcknowledged] = useState(false);

  // Load presets once.
  useEffect(() => {
    fetchDietaryProfiles()
      .then(setPresets)
      .catch((e) => Alert.alert('Could not load presets', (e as Error).message))
      .finally(() => setLoadingPresets(false));
  }, []);

  // Load taste tag chips once (cuisine + flavor families).
  useEffect(() => {
    fetchTags()
      .then(setTags)
      .catch(() => {
        // Tags are optional — taste is skippable, so a load failure
        // just leaves the chip grid empty.
      });
  }, []);

  // Debounced ingredient search (avoid-list step).
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

  // Debounced ingredient search (taste step — separate query).
  useEffect(() => {
    if (step !== 'taste' || tasteQuery.trim().length === 0) {
      setTasteResults([]);
      return;
    }
    const handle = setTimeout(() => {
      searchIngredients(tasteQuery)
        .then(setTasteResults)
        .catch(() => {
          // Non-fatal.
        });
    }, 250);
    return () => clearTimeout(handle);
  }, [tasteQuery, step]);

  const tasteSignalCount =
    draft.likedTagIds.length +
    draft.dislikedTagIds.length +
    draft.likedIngredientIds.length +
    draft.dislikedIngredientIds.length;

  const finalize = async () => {
    const jwt = await getJwt();
    if (!jwt) {
      router.replace('/login?next=%2Fonboarding');
      return;
    }
    try {
      setSaving(true);
      const payload = toProfilePayload(draft, presets);
      // Legal remediation E1 — the done step gates this save behind the
      // allergen-disclaimer toggle, so record the acknowledgment.
      await saveProfile({ ...payload, acknowledge_disclaimer: true }, jwt);
      tracker.track('profile_set', {
        preset_slug: draft.selectedPresetSlugs[0] ?? null,
        avoid_ingredient_count: payload.avoid_ingredient_ids.length,
        avoid_tag_count: payload.avoid_tag_ids.length,
        strictness: payload.strictness,
        taste_signal_count: tasteSignalCount,
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

  // Standalone "Improve my picks" save — taste arrays only, so it can
  // never wipe the user's existing avoid lists (wholesale replace).
  const finalizeTaste = async () => {
    const jwt = await getJwt();
    if (!jwt) {
      router.replace('/login?next=%2Fonboarding%3Fstep%3Dtaste');
      return;
    }
    try {
      setSaving(true);
      await saveTaste(toTastePayload(draft), jwt);
      Alert.alert('Picks updated', 'Your Top Picks just got smarter.');
      router.replace('/');
    } catch (e) {
      const message = (e as Error).message;
      if (message.includes('401')) {
        router.replace('/login?next=%2Fonboarding%3Fstep%3Dtaste');
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
        <Text style={styles.eyebrow}>Step 1 of 5</Text>
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
        <Text style={styles.eyebrow}>Step 2 of 5</Text>
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
        <Text style={styles.eyebrow}>Step 3 of 5</Text>
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

        <Pressable accessibilityLabel="next-to-taste" onPress={() => setStep('taste')} style={styles.primary}>
          <Text style={styles.primaryText}>Next →</Text>
        </Pressable>
      </View>
    );
  }

  if (step === 'taste') {
    return (
      <View style={styles.container}>
        {standalone ? (
          <>
            <Text style={styles.eyebrow}>Improve your picks</Text>
            <Text style={styles.headline}>What do you love?</Text>
            <Text style={styles.body}>
              Tap to love a cuisine or flavor; tap again to pass. This only ranks your menus —
              it never hides anything your dietary filter allows.
            </Text>
          </>
        ) : (
          <>
            <Text style={styles.eyebrow}>Step 4 of 5</Text>
            <Text style={styles.headline}>What do you love?</Text>
            <Text style={styles.body}>
              Tap to love a cuisine or flavor; tap again to pass. Optional — this only ranks your
              Top Picks, it never hides safe food.
            </Text>
          </>
        )}

        <View style={styles.chipGrid}>
          {tags.map((t) => {
            const state = tasteStateOf(t.id, draft.likedTagIds, draft.dislikedTagIds);
            return (
              <Pressable
                key={t.id}
                accessibilityLabel={`taste-tag-${t.slug}`}
                onPress={() => dispatch({ type: 'CYCLE_TASTE_TAG', tagId: t.id })}
                style={[
                  styles.tasteChip,
                  state === 'liked' && styles.tasteChipLiked,
                  state === 'disliked' && styles.tasteChipDisliked,
                ]}
              >
                <Text
                  style={[
                    styles.tasteChipText,
                    state === 'disliked' && styles.tasteChipTextDisliked,
                  ]}
                >
                  {state === 'liked' ? '♥ ' : state === 'disliked' ? '✕ ' : ''}
                  {t.name}
                </Text>
              </Pressable>
            );
          })}
        </View>

        <TextInput
          accessibilityLabel="taste-ingredient-search"
          placeholder="Search a favorite ingredient (e.g. 'basil')"
          value={tasteQuery}
          onChangeText={setTasteQuery}
          style={styles.input}
        />
        <FlatList
          data={tasteResults}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => {
            const state = tasteStateOf(item.id, draft.likedIngredientIds, draft.dislikedIngredientIds);
            return (
              <Pressable
                accessibilityLabel={`taste-ing-${item.slug}`}
                onPress={() => dispatch({ type: 'CYCLE_TASTE_INGREDIENT', ingredientId: item.id })}
                style={[styles.searchRow, state === 'liked' && styles.searchRowAdded]}
              >
                <Text style={[styles.searchName, { flex: 1 }]}>{item.name}</Text>
                <Text style={[styles.addLabel, state === 'liked' && styles.addedLabel]}>
                  {state === 'liked' ? '♥ love' : state === 'disliked' ? '✕ pass' : '+ love'}
                </Text>
              </Pressable>
            );
          }}
          ListEmptyComponent={null}
        />

        <Text style={styles.muted}>{tasteSignalCount} taste signal(s) set</Text>

        {standalone ? (
          <Pressable
            accessibilityLabel="save-taste"
            onPress={finalizeTaste}
            disabled={saving}
            style={[styles.primary, saving && { opacity: 0.5 }]}
          >
            <Text style={styles.primaryText}>{saving ? 'Saving…' : 'Save picks'}</Text>
          </Pressable>
        ) : (
          <Pressable accessibilityLabel="next-to-done" onPress={() => setStep('done')} style={styles.primary}>
            <Text style={styles.primaryText}>Review →</Text>
          </Pressable>
        )}

        <Pressable
          accessibilityLabel="skip-taste"
          onPress={() => (standalone ? router.replace('/') : setStep('done'))}
          style={styles.skip}
        >
          <Text style={styles.skipText}>{standalone ? 'Cancel' : 'Skip for now'}</Text>
        </Pressable>
      </View>
    );
  }

  // step === 'done'
  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>Step 5 of 5</Text>
      <Text style={styles.headline}>Ready?</Text>

      <Text style={styles.body}>
        Avoiding <Text style={{ fontWeight: '700' }}>
          {draft.selectedPresetSlugs.length} preset{draft.selectedPresetSlugs.length === 1 ? '' : 's'}
        </Text> + <Text style={{ fontWeight: '700' }}>
          {draft.manualIngredientIds.length} ingredient{draft.manualIngredientIds.length === 1 ? '' : 's'}
        </Text>, strictness <Text style={{ fontWeight: '700' }}>{draft.strictness}</Text>.
      </Text>

      <Pressable
        accessibilityLabel="acknowledge-disclaimer"
        accessibilityRole="checkbox"
        accessibilityState={{ checked: acknowledged }}
        onPress={() => setAcknowledged((v) => !v)}
        style={styles.ackRow}
      >
        <View style={[styles.ackBox, acknowledged && styles.ackBoxChecked]}>
          {acknowledged && <Text style={styles.ackCheck}>✓</Text>}
        </View>
        <Text style={styles.ackText}>
          I understand BiteWorthy is a planning tool, not a guarantee — results can miss an
          allergen, and I’ll confirm with the restaurant before ordering for a serious allergy.
        </Text>
      </Pressable>

      <Pressable
        accessibilityLabel="finish"
        onPress={finalize}
        disabled={saving || !acknowledged}
        style={[styles.primary, (saving || !acknowledged) && { opacity: 0.5 }]}
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
  ackRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: space['3'],
    padding: space['3'],
    borderRadius: 10,
    borderWidth: 1,
    borderColor: colors.warn,
    backgroundColor: 'rgba(245, 159, 0, 0.1)',
    marginTop: space['2'],
  },
  ackBox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ackBoxChecked: {
    borderColor: colors.bite,
    backgroundColor: colors.bite,
  },
  ackCheck: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.sm,
  },
  ackText: {
    flex: 1,
    fontSize: fontSize.sm,
    color: colors.text,
    lineHeight: 20,
  },
  skip: {
    alignItems: 'center',
    paddingVertical: space['3'],
  },
  skipText: {
    color: colors.textMuted,
    fontWeight: '600',
    fontSize: fontSize.sm,
  },
  tasteChip: {
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgAlt,
    borderRadius: 999,
    paddingHorizontal: space['3'],
    paddingVertical: space['2'],
  },
  tasteChipLiked: {
    borderColor: colors.ok,
    backgroundColor: colors.biteLight,
  },
  tasteChipDisliked: {
    borderColor: colors.bite,
    backgroundColor: colors.biteLight,
  },
  tasteChipText: {
    fontSize: fontSize.sm,
    fontWeight: '600',
    color: colors.text,
  },
  tasteChipTextDisliked: {
    color: colors.biteDark,
    textDecorationLine: 'line-through',
  },
});
