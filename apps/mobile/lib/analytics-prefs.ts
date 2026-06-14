/**
 * Legal remediation E7b — persisted analytics opt-in for mobile.
 *
 * Mobile analytics are OFF by default (App Store privacy posture); the
 * user explicitly opts IN via Settings → Analytics. The choice lives in
 * expo-secure-store so it survives restarts. `_layout` reads it at boot
 * to decide whether to construct a real tracker.
 */
import * as SecureStore from 'expo-secure-store';

const OPT_IN_KEY = 'bw_analytics_opt_in';

/** True only if the user has explicitly opted in. Defaults to false. */
export async function getAnalyticsOptIn(): Promise<boolean> {
  try {
    return (await SecureStore.getItemAsync(OPT_IN_KEY)) === '1';
  } catch {
    return false;
  }
}

export async function setAnalyticsOptIn(value: boolean): Promise<void> {
  try {
    if (value) await SecureStore.setItemAsync(OPT_IN_KEY, '1');
    else await SecureStore.deleteItemAsync(OPT_IN_KEY);
  } catch {
    // SecureStore unavailable (e.g. simulator without keychain) — the
    // default-off posture still holds, so there's nothing to recover.
  }
}

export { OPT_IN_KEY };
