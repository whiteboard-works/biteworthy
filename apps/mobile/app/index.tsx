import { StyleSheet, Text, View } from 'react-native';
import { colors, fontSize, space } from '@biteworthy/ui-tokens';

export default function Home() {
  return (
    <View style={styles.container}>
      <Text style={styles.eyebrow}>BiteWorthy</Text>
      <Text style={styles.headline}>Scan any menu, see only what you can eat.</Text>
      <Text style={styles.body}>
        Pre-MVP. Camera capture and the dietary filter land in the next phases.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingHorizontal: space['6'],
    justifyContent: 'center',
    backgroundColor: colors.bg,
    gap: space['4'],
  },
  eyebrow: {
    color: colors.bite,
    fontSize: fontSize.sm,
    fontWeight: '600',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  headline: {
    fontSize: fontSize['3xl'],
    fontWeight: '700',
    color: colors.text,
    lineHeight: 38,
  },
  body: {
    fontSize: fontSize.base,
    color: colors.textMuted,
  },
});
