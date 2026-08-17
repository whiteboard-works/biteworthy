import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import type { UserPayload } from '@biteworthy/api-types';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { getJwt } from '../../lib/auth';
import { fetchMe, MeValidationError, updateMyHandle } from '../../lib/api/me';

/**
 * Settings → Account — the username (handle) editor. The handle is
 * public identity (review bylines, /users/<handle>), so the copy spells
 * out the consequence: the old address frees up immediately, no
 * redirect. The server stores it lowercase; we adopt what it returns.
 *
 * Validation failures render inline (not Alert): "already taken" is a
 * field-level answer the person corrects in place.
 */
export default function AccountSettingsScreen() {
  const [jwt, setJwt] = useState<string | null>(null);
  const [user, setUser] = useState<UserPayload | null>(null);
  const [handle, setHandle] = useState('');
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getJwt().then((token) => {
      if (cancelled) return;
      if (!token) {
        router.replace('/login?next=%2Fsettings%2Faccount');
        return;
      }
      setJwt(token);
      fetchMe(token)
        .then((u) => {
          if (cancelled) return;
          setUser(u);
          setHandle(u.handle);
        })
        .catch((e) => {
          if (!cancelled) setLoadError((e as Error).message);
        });
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const dirty = user !== null && handle.trim().toLowerCase() !== user.handle;

  const onSave = async () => {
    if (!jwt || !dirty) return;
    try {
      setSubmitting(true);
      setSaveError(null);
      setSaved(false);
      const updated = await updateMyHandle(handle.trim(), jwt);
      setUser(updated);
      setHandle(updated.handle);
      setSaved(true);
    } catch (err) {
      setSaveError(
        err instanceof MeValidationError
          ? `Username ${err.messages[0] ?? 'is not available'}.`
          : (err as Error).message,
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.headline}>Account</Text>
      <Text style={styles.body}>
        Your username appears on your reviews and your public profile. Changing it frees the old
        one for anyone else, and links to the old profile stop working.
      </Text>

      {loadError ? (
        <Text style={styles.error} testID="account-load-error">
          Could not load your account — {loadError}
        </Text>
      ) : !user ? (
        <ActivityIndicator testID="account-loading" color={colors.bite} />
      ) : (
        <>
          <TextInput
            accessibilityLabel="username"
            placeholder="letters, numbers, underscores"
            autoCapitalize="none"
            autoCorrect={false}
            value={handle}
            onChangeText={(v) => {
              setHandle(v);
              setSaved(false);
            }}
            style={styles.input}
          />

          <Pressable
            accessibilityLabel="username-save"
            onPress={() => void onSave()}
            disabled={submitting || !dirty || handle.trim() === ''}
            style={[
              styles.primary,
              (submitting || !dirty || handle.trim() === '') && { opacity: 0.5 },
            ]}
          >
            {submitting ? (
              <ActivityIndicator color={colors.bg} />
            ) : (
              <Text style={styles.primaryText}>Save</Text>
            )}
          </Pressable>

          {saveError ? (
            <Text style={styles.error} testID="username-error">
              {saveError}
            </Text>
          ) : null}
          {saved ? (
            <Text style={styles.saved} testID="username-saved">
              Saved — you are now @{user.handle}.
            </Text>
          ) : null}

          <Pressable
            accessibilityLabel="view-public-profile"
            onPress={() => router.push(`/users/${user.handle}`)}
          >
            <Text style={styles.link}>View your public profile</Text>
          </Pressable>
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 80,
    paddingHorizontal: space['6'],
    backgroundColor: colors.bg,
    gap: space['3'],
  },
  headline: {
    fontSize: fontSize['2xl'],
    fontWeight: '700',
    color: colors.text,
  },
  body: {
    fontSize: fontSize.base,
    color: colors.textMuted,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: space['3'],
    fontSize: fontSize.base,
    color: colors.text,
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
  error: {
    fontSize: fontSize.sm,
    color: colors.danger,
  },
  saved: {
    fontSize: fontSize.sm,
    color: colors.ok,
  },
  link: {
    marginTop: space['2'],
    fontSize: fontSize.sm,
    fontWeight: '600',
    color: colors.bite,
  },
});
