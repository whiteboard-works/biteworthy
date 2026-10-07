import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import type { UserPayload } from '@biteworthy/api-types';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { getJwt } from '../../lib/auth';
import {
  BIO_MAX_LENGTH,
  fetchMe,
  MeError,
  MeValidationError,
  updateMyBio,
  updateMyHandle,
} from '../../lib/api/me';
import {
  CHAT_NOTES_MAX_LENGTH,
  fetchChatNotes,
  ProfileError,
  saveChatNotes,
} from '../../lib/api/profile';

const LOGIN_BOUNCE = '/login?next=%2Fsettings%2Faccount' as const;

/**
 * Settings → Account — the username (handle) editor, the public bio,
 * and the private notes every chat starts with. The handle is
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
    getJwt()
      .then((token) => {
        if (cancelled) return;
        if (!token) {
          router.replace(LOGIN_BOUNCE);
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
            if (cancelled) return;
            // A stored-but-stale token (server-side jti rotation) is
            // the signed-out case, not an error to dead-end on.
            if (e instanceof MeError && e.status === 401) {
              router.replace(LOGIN_BOUNCE);
              return;
            }
            setLoadError((e as Error).message);
          });
      })
      .catch((e) => {
        // SecureStore itself failed — without this the screen spins
        // forever on an unhandled rejection.
        if (!cancelled) setLoadError((e as Error).message);
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
      if (err instanceof MeError && err.status === 401) {
        router.replace(LOGIN_BOUNCE);
        return;
      }
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
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
      // Scrolling closes the keyboard, which otherwise sits over the bio
      // and notes Save buttons with no obvious way to dismiss it.
      keyboardDismissMode="on-drag"
      // The bio and notes fields sit at the bottom of a long screen; on
      // iOS the keyboard would otherwise cover them and their Save.
      automaticallyAdjustKeyboardInsets
    >
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
            testID="username"
            accessibilityLabel="Username"
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
            testID="username-save"
            accessibilityRole="button"
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
            testID="view-public-profile"
            accessibilityRole="button"
            onPress={() => router.push(`/users/${user.handle}`)}
          >
            <Text style={styles.link}>View your public profile</Text>
          </Pressable>

          {jwt ? <BioEditor user={user} jwt={jwt} onSaved={setUser} /> : null}
          {jwt ? <ChatNotesEditor jwt={jwt} /> : null}
        </>
      )}
    </ScrollView>
  );
}

function BioEditor({
  user,
  jwt,
  onSaved,
}: {
  user: UserPayload;
  jwt: string;
  onSaved: (user: UserPayload) => void;
}) {
  const [bio, setBio] = useState(user.bio ?? '');
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const dirty = bio.trim() !== (user.bio ?? '');

  const onSave = async () => {
    if (!dirty) return;
    try {
      setSubmitting(true);
      setError(null);
      setSaved(false);
      const updated = await updateMyBio(bio, jwt);
      onSaved(updated);
      setBio(updated.bio ?? '');
      setSaved(true);
    } catch (err) {
      if (err instanceof MeError && err.status === 401) {
        router.replace(LOGIN_BOUNCE);
        return;
      }
      setError(
        err instanceof MeValidationError
          ? `Bio ${err.messages[0] ?? 'could not be saved'}.`
          : (err as Error).message,
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>About you</Text>
      <Text style={styles.body} testID="bio-public-note">
        A line or two for your public profile. Anyone can read it, so leave out anything you
        wouldn&apos;t post publicly — your dietary settings stay private either way.
      </Text>
      <TextInput
        testID="bio"
        accessibilityLabel="About you"
        placeholder="Taco hunter. Always asking about the fryer."
        multiline
        maxLength={BIO_MAX_LENGTH}
        value={bio}
        onChangeText={(v) => {
          setBio(v);
          setSaved(false);
        }}
        style={[styles.input, styles.multiline]}
      />
      <Text style={styles.counter}>
        {bio.length}/{BIO_MAX_LENGTH}
      </Text>
      <SaveButton testID="bio-save" label="Save bio" busy={submitting} disabled={!dirty} onPress={onSave} />
      {error ? (
        <Text style={styles.error} testID="bio-error">
          {error}
        </Text>
      ) : null}
      {saved ? (
        <Text style={styles.saved} testID="bio-saved">
          Saved.
        </Text>
      ) : null}
    </View>
  );
}

/**
 * Private notes the chat reads as context. They never filter anything,
 * and the help text says so before anyone writes an allergy here.
 * Loads on its own so a failure here leaves the rest of the screen up.
 */
function ChatNotesEditor({ jwt }: { jwt: string }) {
  const [stored, setStored] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetchChatNotes(jwt)
      .then((n) => {
        if (cancelled) return;
        setStored(n);
        setNotes(n ?? '');
        setLoaded(true);
      })
      .catch((e) => {
        if (cancelled) return;
        if (e instanceof ProfileError && e.status === 401) {
          router.replace(LOGIN_BOUNCE);
          return;
        }
        setLoadError((e as Error).message);
      });
    return () => {
      cancelled = true;
    };
  }, [jwt]);

  const dirty = notes.trim() !== (stored ?? '');

  const onSave = async () => {
    if (!dirty) return;
    try {
      setSubmitting(true);
      setError(null);
      setSaved(false);
      const updated = await saveChatNotes(notes, jwt);
      setStored(updated);
      setNotes(updated ?? '');
      setSaved(true);
    } catch (err) {
      if (err instanceof ProfileError && err.status === 401) {
        router.replace(LOGIN_BOUNCE);
        return;
      }
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>Notes for the assistant</Text>
      <Text style={styles.body} testID="chat-notes-help">
        Anything every chat should know about you, like who you&apos;re cooking for or how spicy
        you like it. Private to you. Notes don&apos;t hide dishes — add allergies to your avoid
        list so the menu filter catches them.
      </Text>
      {loadError ? (
        <Text style={styles.error} testID="chat-notes-load-error">
          Could not load your notes — {loadError}
        </Text>
      ) : !loaded ? (
        <ActivityIndicator color={colors.bite} />
      ) : (
        <>
          <TextInput
            testID="chat-notes"
            accessibilityLabel="Notes for the assistant"
            placeholder="Cooking for two kids. Mild spice only."
            multiline
            maxLength={CHAT_NOTES_MAX_LENGTH}
            value={notes}
            onChangeText={(v) => {
              setNotes(v);
              setSaved(false);
            }}
            style={[styles.input, styles.multiline]}
          />
          <Text style={styles.counter}>
            {notes.length}/{CHAT_NOTES_MAX_LENGTH}
          </Text>
          <SaveButton
            testID="chat-notes-save"
            label="Save notes for the assistant"
            busy={submitting} disabled={!dirty} onPress={onSave} />
          {error ? (
            <Text style={styles.error} testID="chat-notes-error">
              {error}
            </Text>
          ) : null}
          {saved ? (
            <Text style={styles.saved} testID="chat-notes-saved">
              Saved. New chat messages will use them.
            </Text>
          ) : null}
        </>
      )}
    </View>
  );
}

function SaveButton({
  testID,
  label,
  busy,
  disabled,
  onPress,
}: {
  testID: string;
  /** Spoken name; both Save buttons read "Save", so say which. */
  label: string;
  busy: boolean;
  disabled: boolean;
  onPress: () => Promise<void>;
}) {
  return (
    <Pressable
      testID={testID}
      accessibilityLabel={label}
      accessibilityRole="button"
      accessibilityState={{ disabled: busy || disabled, busy }}
      onPress={() => void onPress()}
      disabled={busy || disabled}
      style={[styles.primary, (busy || disabled) && { opacity: 0.5 }]}
    >
      {busy ? <ActivityIndicator color={colors.bg} /> : <Text style={styles.primaryText}>Save</Text>}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  content: {
    paddingTop: 80,
    paddingBottom: space['12'],
    paddingHorizontal: space['6'],
    gap: space['3'],
  },
  section: {
    marginTop: space['6'],
    gap: space['3'],
  },
  sectionTitle: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
  },
  multiline: {
    minHeight: 96,
    textAlignVertical: 'top',
  },
  counter: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    textAlign: 'right',
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
