# AGENTS.md — apps/mobile (Expo)

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** The Expo (React Native) mobile client for BiteWorthy, built/released via EAS. Like the web app, it renders the visible/hidden split the Rails API sends rather than computing one — `@biteworthy/filter-engine` gives it wire types and presentation helpers, not a filter. It additionally has an Expo-managed dependency set that must stay SDK-aligned. (See the repo-root `AGENTS.md` for the single-filter and analytics contracts.)

GitHub surfaces only P0/P1 findings. CI runs the JS typecheck/lint/Jest suite (`ci-js`) and the Expo SDK alignment check (`expo-align`) — don't restate those.

Block a PR (P0/P1) when it:

- **Hand-bumps an Expo-managed dependency to an unaligned version.** The sanctioned path is `npx expo install --fix` (enforced by `expo-align`); a manual version change to an Expo-managed package (`expo-*`, `react-native`, `jest-expo`, etc.) that diverges from the SDK's `bundledNativeModules` breaks the native build.
- **Decides visible/hidden in a screen/component.** Render the server's `status` and `reasons`; never derive them from the item's `ingredient_ids` / `tag_ids` or from a stored profile. The taxonomy is hierarchical and the device does not have it, so a local re-derivation under-filters and can show an unsafe item as safe.
- **Emits an analytics event off-contract.** Use the `@biteworthy/analytics` `EVENTS` names/shapes; never re-add the legal-E7 health fields to `profile_set`.

For architecture and conventions, also follow CLAUDE.md and the repo-root `AGENTS.md`.
<!-- END codex-review-guidelines -->
