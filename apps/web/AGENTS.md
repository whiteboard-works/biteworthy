# AGENTS.md — apps/web (Next.js)

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** The Next.js web client for BiteWorthy. It does **not** compute the visible/hidden menu set — the Rails API does, and this app renders the `status` / `reasons` each item arrives with. `@biteworthy/filter-engine` supplies the wire types and the presentation helpers (reason chips, section grouping, "show anyway" overrides, Top Picks selection, share-token encoding), not a filter. (See the repo-root `AGENTS.md` for the single-filter and analytics contracts.)

GitHub surfaces only P0/P1 findings. CI runs `pnpm typecheck` / `lint` / `test` (`ci-js`) — don't restate those.

Block a PR (P0/P1) when it:

- **Decides visible/hidden in the client.** A component must render the server's `status` and `reasons`, never derive them — not from the item's `ingredient_ids` / `tag_ids`, not from a stored profile. The taxonomy is hierarchical and the browser does not have it, so a local re-derivation under-filters: someone avoiding `dairy` would be shown a dish tagged `dairy-cheddar` as safe.
- **Emits an analytics event off-contract.** Use the `@biteworthy/analytics` `EVENTS` names and property shapes; never add the legal-E7 health fields (`preset_slug`, `strictness`, avoid-list counts) back to `profile_set`.
- **Leaks a secret into the client bundle.** Only `NEXT_PUBLIC_*` env vars may reach client code; a non-`NEXT_PUBLIC_` server key imported into a `'use client'` component (or otherwise reachable from the client bundle) ships to the browser.

For architecture and conventions, also follow CLAUDE.md and the repo-root `AGENTS.md`.
<!-- END codex-review-guidelines -->
