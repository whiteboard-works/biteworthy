# AGENTS.md — apps/mobile (Expo)

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** The Expo (React Native) mobile client for BiteWorthy, built/released via EAS. Like the web app, it depends on the shared filter engine and analytics contract; it additionally has an Expo-managed dependency set that must stay SDK-aligned. (See the repo-root `AGENTS.md` for the filter-parity and analytics contracts.)

GitHub surfaces only P0/P1 findings. CI runs the JS typecheck/lint/Jest suite (`ci-js`) and the Expo SDK alignment check (`expo-align`) — don't restate those.

Block a PR (P0/P1) when it:

- **Hand-bumps an Expo-managed dependency to an unaligned version.** The sanctioned path is `npx expo install --fix` (enforced by `expo-align`); a manual version change to an Expo-managed package (`expo-*`, `react-native`, `jest-expo`, etc.) that diverges from the SDK's `bundledNativeModules` breaks the native build.
- **Re-implements avoid-list filtering in a screen/component** instead of calling `@biteworthy/filter-engine` — it must stay in parity with the server filter, or an unsafe item can render as safe.
- **Emits an analytics event off-contract.** Use the `@biteworthy/analytics` `EVENTS` names/shapes; never re-add the legal-E7 health fields to `profile_set`.

For architecture and conventions, also follow CLAUDE.md and the repo-root `AGENTS.md`.
<!-- END codex-review-guidelines -->
