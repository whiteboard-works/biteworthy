# AGENTS.md — apps/web (Next.js)

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** The Next.js web client for BiteWorthy. It pre-computes the visible/hidden menu set on the client via the shared filter engine, so its correctness depends on staying byte-for-byte in agreement with the Rails server filter. (See the repo-root `AGENTS.md` for the filter-parity and analytics contracts.)

GitHub surfaces only P0/P1 findings. CI runs `pnpm typecheck` / `lint` / `test` (`ci-js`) — don't restate those.

Block a PR (P0/P1) when it:

- **Re-implements avoid-list filtering in a component** instead of calling `@biteworthy/filter-engine`. The shared engine is the single source of truth; any local re-implementation diverges from the server and can render an unsafe item as safe.
- **Emits an analytics event off-contract.** Use the `@biteworthy/analytics` `EVENTS` names and property shapes; never add the legal-E7 health fields (`preset_slug`, `strictness`, avoid-list counts) back to `profile_set`.
- **Leaks a secret into the client bundle.** Only `NEXT_PUBLIC_*` env vars may be referenced in client code; a server key referenced from a client component or `is:inline`-style script ships to the browser.

For architecture and conventions, also follow CLAUDE.md and the repo-root `AGENTS.md`.
<!-- END codex-review-guidelines -->
