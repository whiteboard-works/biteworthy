import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Linking,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Link, router, useLocalSearchParams } from 'expo-router';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { AuthError, signup } from '../lib/auth';

// The legal pages are web-only; open the hosted versions in the device
// browser (there are no in-app /terms or /privacy routes).
const LEGAL_SITE = 'https://bite-worthy.com';

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
  const [ageConfirmed, setAgeConfirmed] = useState(false);
  const [termsAccepted, setTermsAccepted] = useState(false);
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
    if (!ageConfirmed) {
      Alert.alert('Age confirmation required', 'You must confirm you are at least 13 years old.');
      return;
    }
    if (!termsAccepted) {
      Alert.alert('Agreement required', 'You must agree to the Terms of Service and Privacy Policy.');
      return;
    }
    try {
      setSubmitting(true);
      await signup(email, password, ageConfirmed, termsAccepted);
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
        accessibilityLabel="age-confirm"
        accessibilityRole="checkbox"
        accessibilityState={{ checked: ageConfirmed }}
        onPress={() => setAgeConfirmed((v) => !v)}
        style={styles.ageRow}
      >
        <View style={[styles.ageBox, ageConfirmed && styles.ageBoxChecked]}>
          {ageConfirmed && <Text style={styles.ageCheck}>✓</Text>}
        </View>
        <Text style={styles.ageText}>I am at least 13 years old.</Text>
      </Pressable>

      <Pressable
        accessibilityLabel="terms-accept"
        accessibilityRole="checkbox"
        accessibilityState={{ checked: termsAccepted }}
        onPress={() => setTermsAccepted((v) => !v)}
        style={styles.ageRow}
      >
        <View style={[styles.ageBox, termsAccepted && styles.ageBoxChecked]}>
          {termsAccepted && <Text style={styles.ageCheck}>✓</Text>}
        </View>
        <Text style={styles.ageText}>I agree to the Terms of Service and Privacy Policy.</Text>
      </Pressable>
      <View style={styles.legalLinks}>
        <Pressable accessibilityLabel="open-terms" onPress={() => void Linking.openURL(`${LEGAL_SITE}/terms`)}>
          <Text style={styles.linkInline}>Terms of Service</Text>
        </Pressable>
        <Text style={styles.ageText}> · </Text>
        <Pressable accessibilityLabel="open-privacy" onPress={() => void Linking.openURL(`${LEGAL_SITE}/privacy`)}>
          <Text style={styles.linkInline}>Privacy Policy</Text>
        </Pressable>
      </View>

      <Pressable
        accessibilityLabel="signup-submit"
        onPress={onSubmit}
        disabled={submitting || !ageConfirmed || !termsAccepted}
        style={[styles.primary, (submitting || !ageConfirmed || !termsAccepted) && { opacity: 0.5 }]}
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
  ageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space['2'],
    marginTop: space['2'],
  },
  ageBox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ageBoxChecked: {
    borderColor: colors.bite,
    backgroundColor: colors.bite,
  },
  ageCheck: {
    color: colors.bg,
    fontWeight: '700',
    fontSize: fontSize.sm,
  },
  ageText: {
    fontSize: fontSize.sm,
    color: colors.text,
  },
  linkInline: {
    color: colors.bite,
    fontWeight: '600',
    fontSize: fontSize.sm,
  },
  legalLinks: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 30,
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
