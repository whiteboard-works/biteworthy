import { StyleSheet, Text } from 'react-native';
import { colors, fontSize, radius, space } from '@biteworthy/ui-tokens';

/** A small neutral fact about a dish (its price, its menu section). */
export function InfoChip({ testID, children }: { testID: string; children: string }) {
  return (
    <Text style={styles.infoChip} testID={testID}>
      {children}
    </Text>
  );
}

const styles = StyleSheet.create({
  infoChip: {
    backgroundColor: colors.bgAlt,
    borderRadius: radius.pill,
    paddingHorizontal: space['2'],
    paddingVertical: 2,
    fontSize: fontSize.xs,
    fontWeight: '600',
    color: colors.textMuted,
    overflow: 'hidden',
  },
});
