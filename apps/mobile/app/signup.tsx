import { useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Link, router, useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { AuthError, signup } from '../lib/auth';

/**
 * Phase 4.1 — mobile signup screen. Mirrors the web signup; defaults
 * the post-signup destination to /onboarding so a fresh account
 * lands on the dietary-filter setup.
 */
export default function SignupScreen() {
  const params = useLocalSearchParams<{ next?: string }>();
  const next = typeof params.next === 'string' && params.next.length > 0 ? params.next : '/onboarding';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const onSubmit = async () => {
    if (!email || !password) {
      Alert.alert('Missing info', 'Email and password required.');
      return;
    }
    if (password.length < 8) {
      Alert.alert('Password too short', 'Use 8 or more characters.');
      return;
    }
    try {
      setSubmitting(true);
      await signup(email, password);
      router.replace(next);
    } catch (err) {
      const status = err instanceof AuthError ? err.status : 0;
      const message = status === 422 ? 'That email is already in use.' : (err as Error).message;
      Alert.alert('Sign-up failed', message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>BiteWorthy</Text>
      <Text style={styles.headline}>Create account</Text>
      <Text style={styles.body}>Free. We'll save your dietary filter for next time.</Text>

      <TextInput
        accessibilityLabel="email"
        placeholder="Email"
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
        value={email}
        onChangeText={setEmail}
        style={styles.input}
      />
      <TextInput
        accessibilityLabel="password"
        placeholder="Password (8+ chars)"
        autoCapitalize="none"
        secureTextEntry
        value={password}
        onChangeText={setPassword}
        style={styles.input}
      />

      <Pressable
        accessibilityLabel="signup-submit"
        onPress={onSubmit}
        disabled={submitting}
        style={[styles.primary, submitting && { opacity: 0.5 }]}
      >
        {submitting ? (
          <ActivityIndicator color={colors.bg} />
        ) : (
          <Text style={styles.primaryText}>Create account</Text>
        )}
      </Pressable>

      <Link href={`/login?next=${encodeURIComponent(next)}`} style={styles.link}>
        <Text style={styles.linkText}>Already have an account? Sign in</Text>
      </Link>
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
    color: colors.textMuted,
    marginBottom: space['3'],
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
    marginTop: space['3'],
  },
  primaryText: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.base,
  },
  link: {
    marginTop: space['4'],
    alignSelf: 'center',
  },
  linkText: {
    color: colors.bite,
    fontWeight: '600',
    fontSize: fontSize.sm,
  },
});
