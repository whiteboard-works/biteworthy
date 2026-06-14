import { useEffect, useState } from 'react';
import { StyleSheet, Switch, Text, View } from 'react-native';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';
import { getAnalyticsOptIn, setAnalyticsOptIn } from '../../lib/analytics-prefs';

/**
 * Legal remediation E7b — the Settings → Analytics screen the Privacy
 * Policy promises ("On mobile, analytics are off by default and only
 * fire if you enable them in Settings → Analytics").
 *
 * The toggle persists the opt-in to expo-secure-store; the root layout
 * reads it at boot to decide whether to construct a real tracker, so
 * the change takes effect on the next app launch. Analytics never carry
 * the dietary profile (see packages/analytics).
 */
export default function AnalyticsSettingsScreen() {
  const [optedIn, setOptedIn] = useState<boolean | null>(null);

  useEffect(() => {
    let cancelled = false;
    getAnalyticsOptIn().then((v) => {
      if (!cancelled) setOptedIn(v);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const onToggle = (next: boolean) => {
    setOptedIn(next);
    void setAnalyticsOptIn(next);
  };

  return (
    <View style={styles.container}>
      <Text style={styles.headline}>Analytics</Text>
      <Text style={styles.body}>
        Analytics are off by default. Turn them on to share anonymous product usage that helps us
        improve BiteWorthy. We never send your dietary profile — what you avoid, your presets, or
        your strictness.
      </Text>

      <View style={styles.row}>
        <Text style={styles.rowLabel}>Allow anonymous analytics</Text>
        <Switch
          accessibilityLabel="analytics-opt-in"
          disabled={optedIn === null}
          value={optedIn === true}
          onValueChange={onToggle}
          trackColor={{ true: colors.bite, false: colors.border }}
        />
      </View>

      <Text style={styles.note} accessibilityLabel="analytics-state">
        {optedIn === null
          ? 'Loading…'
          : optedIn
            ? 'On. Takes effect the next time you open the app.'
            : 'Off. No analytics are sent.'}
      </Text>
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
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: space['3'],
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: colors.border,
    marginTop: space['3'],
  },
  rowLabel: {
    fontSize: fontSize.base,
    fontWeight: '600',
    color: colors.text,
  },
  note: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
});
