# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
live phases link to a `docs/plans/phase-N.md` subplan with the gory
details (shipped subplans are archived under `docs/plans/archive/`).

## Status

**Phases 0–8 + the legal-remediation arc have all shipped** (#112–#346).
The product is feature-complete: anyone-can-scan ingestion, the
real-world mobile scan loop, "most likely to enjoy" taste ranking, and
honest privacy/ToS + E1–E13 engineering are all on master. The full
per-PR history, each phase's demo, and the resolved follow-ups live in
[`status-archive/roadmap-phases-0-8.md`](status-archive/roadmap-phases-0-8.md);
the per-task acceptance criteria are in `docs/plans/archive/`.

Everything remaining is human-credential-gated launch work — see
**Next up** and `docs/launch-readiness.md`.

## MCP pivot (active, 2026-08-07)

Ingestion is being rebuilt around a conversation instead of a swipe-verify
UI, and the tool layer becomes the primary design surface for the whole
product: one command layer with two adapters over it — MCP tool classes for
Claude clients and the first-party chat, thin REST controllers for the light
UI. The extraction engine (prompt, schema, deterministic resolver, staging
tables) is kept and wrapped as tools; the swipe UI and the Solid Queue stage
machine are what get replaced.

**Plan + decisions: [`docs/plans/mcp-pivot.md`](plans/mcp-pivot.md).**
Mechanics: [`docs/mcp.md`](mcp.md). Read the plan's Decisions and Traps
tables before picking up a phase — several are non-obvious from the code.

- [x] M1 — tool registry + `POST /mcp` (discovery + profile tools, Devise-JWT auth)
- [x] M2 — ingestion tools over the existing engine; explicit job dispatch; old ingest surfaces removed
- [x] M3a — community domains: reviews, suggestions, claims, history, `create_restaurant` (30 tools)
- [x] M3b — admin domains: restaurant/menu structure, item deep-edit, taxonomy, moderation, users (43 tools)
- [x] M3c — topology (`biteworthy://topology` resource + `describe_capabilities`); 44 tools
- [x] M4a — chat loop: `Chat::AgentLoop`, conversations/messages, confirmation gate, spend ceiling
- [x] M4b — chat HTTP surface: SSE endpoint, attachment upload, conversation replay
- [x] M5 — chat UI in `apps/web`; web scan entry points restored (mobile still has none)
- [x] M6 — deferred tool loading (`defer_loading` + tool search) — **shipped as C7**
- [ ] M7 — REST adapters over tools for the discovery + profile controllers; re-run openapi + api-types codegen
- [x] M8 — public MCP: OAuth 2.1 (doorkeeper, PKCE-only), RFC 9728 + RFC 8414 metadata, RFC 7591 registration, RFC 8707 audience validation, consent in apps/web, connected-app revocation at `/profile/settings`

**Web scanning is back as of M5** — `/chat`, reached from the hero CTA, the
site header, and the restaurants empty state. **Mobile chat shipped
2026-08-08** (#532/#533), which this paragraph claimed for two days it had
not: the Expo app polls `GET /conversations/:id/events` rather than reading
SSE, because React Native's XHR-backed fetch exposes no readable body. It
renders plain text bubbles — markdown, tool cards, and usage pills are still
web-only.

## Chat engine (active, 2026-08-08)

M1–M5 shipped a chat that works. What it lacks is the layer around the
loop: a turn runs inline in `ActionController::Live` and dies with the
request, two tabs interleave, there is no abort, no per-round metrics, and
a failure the user saw vanishes on their next reload. This arc treats the
agentic loop as a distributed-systems problem — locks, leases, replay
invariants, idempotent repair.

**Plan + decisions: [`docs/plans/chat-engine.md`](plans/chat-engine.md).**
Read its Decisions and Safety-properties tables before picking up a phase.

- [x] C1 — one tool boundary: argument validation + contained tool bugs in `Tools::Base`, both doors
- [x] C2 — confirmation bound to the exact call; avoid-list removals gated by code, not prose
- [x] C3 — run lifecycle: Postgres lock/lease, abort flag, stop endpoint, per-round token metrics
- [x] C4 — turns run in a job; SSE becomes a replayable relay; pending-turn queue; stop button
- [x] C5 — prompts as ordered sections + a volatile trailing block (profile snapshot, page context)
- [x] C6 — grounding review on dietary answers (Safety Property 1, enforced not instructed)
- [x] C7 — deferred tool loading (M6): 67–79% off a cold turn; per-tool progress text
- [x] C8 — exact cost accounting: micro-cents, the reviewer's spend, `run_token` on every accrual
- [x] C9 — cache the transcript, not just the prompt (~69% off a long turn's input, estimated)

M1 extracted the menu filter out of `ItemsController` into `Menus::Filter` /
`Menus::Labels` / `Menus::Query` so the `get_menu` tool and the REST endpoint
share one implementation — that logic is the product's safety story and must
not exist twice.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Launch gates** (human, not the loop): the L1–L5 legal gates (remove
`/privacy` + `/terms` DRAFT banners, lawyer sign-off, DMCA agent
registration) in `docs/plans/legal-remediation-followups.md`, alongside
the credential-gated wiring below. `docs/launch-readiness.md` is the
linear human path from "code complete" to launch.

1. **[BLOCKED] Phase 5.9-wiring — generate binary assets + screenshot routes + EAS submit** (followup to #180). Needs Apple Developer ($99/yr) + Google Play Console ($25 one-time) + lawyer signoff on `/privacy` + `/terms` + designed icon-source.svg.
2. ~~**A bot-merged `apps/api` PR does not deploy — dispatch `deploy-api` by hand.**~~ **RESOLVED 2026-08-09; verified 2026-08-14.** The `AUTOMERGE_TOKEN` secret exists, so `auto-merge.yml` no longer merges with `GITHUB_TOKEN` and GitHub's recursion guard no longer swallows the run. Evidence: tonight's auto-merged `apps/api` PRs (#608, #610, #611) all show `merged_by=wbwSoftware` rather than `github-actions[bot]` — the exact check this item prescribed — and `deploy-api.yml` fired `on: push` for each, all successful. No hand-dispatch needed. **Kept in the queue rather than deleted, because it can come back:** `AUTOMERGE_TOKEN` is a fine-grained PAT, and `auto-merge.yml` reads `secrets.AUTOMERGE_TOKEN || secrets.GITHUB_TOKEN` — and those two words hide two *different* failure modes. **Secret deleted:** the expression picks `GITHUB_TOKEN` and the original bug returns silently, master looking shipped while the box is stale. **Secret still set but the PAT expired or was revoked:** `||` tests whether the value is empty, not whether it works, so it yields the dead token and the auto-merge step fails auth instead — PRs simply stop merging, which is at least visible as a red `enable` check. Diagnostic worth not relearning — check `merged_by` on a recently auto-merged `apps/api` PR; `github-actions[bot]` means the token is gone and API changes have stopped shipping. (The GHCR PAT in `.kamal/secrets` expires ~2026-10-12 and breaks deploys the same way, though that one at least fails loudly.)

**Admin backoffice workstream — SHIPPED 2026-07-30** (#467–#481,
session-driven): all admin capability lives in `apps/web` `/admin`
(dashboard, ingestion moderation, reviews/suggestions, taxonomy,
restaurants/items/users), backed by the `Api::V1::Admin` JSON
namespace (`require_admin!` → 404; `users.is_admin` via
`admin:grant/sync` rake tasks). Avo, the ERB `/admin/dashboard`, and
the `ADMIN_USERNAME`/`ADMIN_PASSWORD` basic-auth gate are deleted.
Deferred to v2: taxonomy merge + subtree rename, join-level
ingredient/tag editing, debounced admin search.

**Upstream-editing workstream — SHIPPED 2026-07-31** (#483–#489):
data is fixable as far upstream as possible. Staged items are fully
editable before accept (name, description, ingredient/tag chips,
prices, add-ons), and admins can edit anything at a restaurant — item
deep-edit, taxonomy chips, menus/sections, address and hours.
Split-shift hours followed in #490, addon editing in #491. Deferred to
v2: taxonomy merge + subtree rename, and an overlap guard
on hour ranges (a day may now hold contradictory ranges — harmless
while nothing but the admin editor reads `hours`, worth closing before
a public hours display ships).

- [x] E1 — API: permit `prices_payload` in staged-item edits; real payload row schemas
- [x] E2 — web: verify-flow edit panel (name, description, chips, prices); admin run review inherits
- [x] E3 — API: admin item deep-edit (variants, modifiers, ingredient/tag join sync, section move)
- [x] E4 — web: admin item deep-edit panel
- [x] E5 — API: admin menus, sections, addresses, hours
- [x] E6 — web: admin structure + place editors
- [x] E7 — API: admin delete — archive by default, hard delete for super admins
- [x] E8 — web: admin delete/archive controls on the six admin pages

Invariants: join `confidence` never directly editable (admin chip edits
write `confirmed`/`human`, removals row-by-row so the denormalized
arrays stay honest); matched re-scan cards stay append-only.

Other than that workstream and the exploration follow-ups below, **no
remaining loop-shippable work.** Every loop-shippable launch piece is on
master; the rest of the queue is human-credential-gated.

## Open follow-ups

Loop-surfaced tasks that don't belong to a shipped phase. Humans triage
these into the launch path or a future phase. (Resolved follow-ups are
in the [roadmap history](status-archive/roadmap-phases-0-8.md).)

- **Mobile `/settings/analytics` is an orphan route (2026-08-16)** — the
  screen exists (`apps/mobile/app/settings/analytics.tsx`, the analytics
  opt-in switch) but nothing in the app navigates to it; the only
  references are prose comments. Surfaced while placing the version line
  for #624. Needs either a settings/about hub linked from home, or a
  direct entry point — a privacy-relevant control shouldn't be reachable
  only by deep link.
- **User-exploration findings (2026-08-15)** — a live-product walkthrough
  left a severity-ordered findings brief with a small-fixes checklist in
  [`plans/ux-exploration-2026-08-15.md`](plans/ux-exploration-2026-08-15.md).
  The checklist items are loop-shippable (several PRs already in flight,
  tracked in the doc); the four bigger findings (ingestion `gap?` widening,
  confirmation backlog, item-page ingredients panel, anonymous scan entry)
  need human triage into a phase before any loop picks them up.

- **Schema-review leftovers (2026-07-31)** — the review that produced
  #493 and #496 left three items the loop can't finish alone. (Two
  others — promoting the CHECK constraints to VALID, and the
  case-sensitive `users.email` — were closed in #496 once a read-only
  prod audit cleared them.)
  1. ~~**`items.popularity` is read but never written.**~~ **Closed
     2026-08-14.** Dropped in two deploys: #601 removed every reader
     (the `TasteScoring` weight, the menu's `popularity DESC` ordering,
     the Top Picks tie-break, the item payload field) and shipped;
     #603 dropped the column once that was live. A read-only production
     audit gated the irreversible half and came back empty — 89 items,
     none non-zero — so the scoring term really was structurally zero in
     production. `restaurant_visits` and `favorite_items` remain the
     obvious inputs if a real popularity signal is ever wanted.
  2. ~~**`restaurants.slug` is globally unique.**~~ **Closed 2026-08-14
     — generation is city-aware; the column stays globally unique.**
     `Restaurants::Create#unique_slug_for` now falls back to
     `taco-bell-durango` before `taco-bell-2`, and only when the
     collision is genuinely across cities. The column was deliberately
     *not* moved to a `[city_id, slug]` index: `find_by_id_or_slug!`
     and the web route `/restaurants/[slug]` carry no city, so per-city
     uniqueness makes `find_by!(slug:)` ambiguous — it would return
     whichever row Postgres reached first, which for a filtered menu is
     another restaurant's dietary data. City #2 is unblocked either way,
     and every URL already issued still resolves. One rough edge left:
     `Biteworthy::DurangoSeed` looks a restaurant up by `[city, slug]`,
     so seeding a second city with a name that collides on slug fails
     that row loudly (`RecordNotUnique`, caught per row and reported)
     rather than corrupting the first city's. The CSV's explicit `slug`
     column is the operator's escape hatch.
  3. **`user_profiles.prefer_tag_ids` has no reader.** Onboarding and
     the profile endpoints write it; nothing ranks by it (taste signals
     replaced it). Either feed it into `TasteScoring` or drop it and
     its writers.

- **The avoid lists accept ids that mean nothing** — the *soft* taste
  arrays validate that their UUIDs resolve; the *hard* safety arrays
  did not, so an unknown id (or a slug, which casts to NULL in a
  `uuid[]` column) saved fine and then matched no dish. The same hole
  sat behind the share link, where `ProfileToken.decode` checked
  `ai`/`at` only as "an array of strings". **Fixed in #605**, with two
  deliberate asymmetries worth keeping straight. `avoid_ids_are_real`
  checks only ids a save *introduces*, because those arrays are
  rewritten wholesale and re-checking an echoed-back stale id would
  lock someone out of editing their own safety filter. The token is the
  opposite — `Menus::Filter.from_token` refuses it whole if any id no
  longer resolves, because a stale link is exactly when "this menu is
  filtered to my profile" stops being true, and shape alone does not
  close that: a well-formed UUID naming nothing matches no dish either.
  A person can fix a profile; nobody can fix a link.

- ~~**`/login?next=` is an open redirect**~~ — **closed 2026-08-14 (#600).**
  It was in `/signup` as well, which this entry never said. The fix it
  prescribed — `startsWith('/')`, reject `//` — would not have worked,
  and that was measured rather than argued: URL parsing normalises a
  backslash to a slash for special schemes, so `/\evil.com` starts with
  one slash and still resolves off-origin; and dot-segment resolution
  can *create* an authority on the way out, so `.//evil.com` passes an
  input check and then serialises to the protocol-relative `//evil.com`.
  Both classes bite after the check, not before, so `lib/safe-next.ts`
  re-resolves the value it returns instead of inspecting the one it got.
  See `docs/status.md` 2026-08-14.

- **`pnpm build` fails on clean master** — `@biteworthy/mobile#build`
  (`expo export`) exits non-zero with no local changes, and `ci-js.yml`
  never runs `build`, so nothing catches it. Not blocking today (Vercel
  builds web on its own and mobile ships through EAS), but it means the
  root `pnpm build` cannot be used as a pre-push check.

- **`Chat::Titler` has no VCR cassette** — surfaced by Codex on #599.
  `GroundingReview` has two under `spec/cassettes/chat/`; the titler has
  none, because `titler_spec` injects a `ScriptedClient` and never makes
  an HTTP request. Nothing therefore checks the titler's real request
  shape — model id, structured-output config, parser — against Anthropic,
  so a change to any of them fails silently in production rather than in
  CI. Recording one needs a live call with a real key. Not a blocker
  (the call has shipped and works), but it is an inconsistency in how
  the two model calls in the chat are covered.

- **MCP token scopes fail open** — `Tools::Scopes.satisfied?` treats an
  empty grant as unrestricted, so "granted nothing" and "granted
  everything" are the same value: `scopes: ["", "  "]` survives
  `compact_blank` as `[]` and mints a credential reaching all thirteen
  gated domains. **Fixed in #604** — full access is the named scope `*`,
  `McpToken` requires at least one, and `Tools::Context` separates an
  omitted `scopes` key (nothing is narrowing this call) from a stated
  `[]` (a credential was consulted and granted nothing).

- **Onboarding-chip flake recurred (3rd occurrence)** — the test fixed
  in #199 ("renders a chip per preset once the fetch resolves") timed
  out again on #304's CI runner (suite took 16.5s; 5s per-test cap).
  The findByLabelText fix helped locally but slow CI runners still trip
  it. Candidate fixes: bump that test's timeout to 15s, or
  jest.setTimeout for the file. One-line change; fold into the next
  mobile PR.
- **`chat.render.test.tsx › turn analytics › reports what actually
  happened` is flaky, and the cause is app-side** — reproduces locally
  at roughly 3-in-6 on a full-suite run (never on a single-file run),
  on master as well as on any branch. Two alternating failures,
  `tool_count: 0` and `outcome: "error"`, which is the signature of
  something *else* consuming this test's queued
  `mockResolvedValueOnce` values: whichever of the two gets stolen
  decides which assertion breaks. The consumer is a `watch` loop from
  an earlier test that was mid-`setTimeout(POLL_MS)` when the test
  ended — `watch` (`apps/mobile/app/chat.tsx`) polls until the server
  says `running: false` or `MAX_POLL_MS` elapses and has **no
  unmount cancellation**, so it outlives the screen. `jest.clearAllMocks()`
  does not drain a once-queue, but draining would not fix this anyway
  while a live consumer exists. The real fix is aborting the poll when
  the screen goes away, which is worth having in its own right (a
  backgrounded chat should stop polling), and is an app change rather
  than a test tweak.

- **Phase 6.5/6.6 codex P2 followups (web+mobile verify UX)** — from
  #304's review, all reasonable, none blocking: (1) logged-out users
  hit the create step before any 401 redirect — picker should redirect
  like upload does; (2) no edit-before-accept path in the web verify
  list (API supports `edited`; mobile verify has it); (3) "did you mean"
  cards offer other users' DRAFTS as reusable targets, which then 403 at
  scan time — filter candidates to published-or-own; (4) web verify
  polling stops permanently on one transient fetch failure — retry with
  backoff. Also applies partly to mobile picker (3).
- **Ingestion + restaurant endpoints lack rswag specs** (noted while
  shipping 6.1/6.2). `POST /ingestion_runs`, `PATCH .../items/:id`,
  `POST /restaurants` aren't in `docs/openapi.json`, so api-types stays
  hand-written for them. One PR could rswag the lot + re-run codegen.
- **Auto-merge race lost a follow-on commit (#150, #172)** — twice a
  second commit was added before CI finished and auto-merge had already
  enabled on the first sha and squashed without the second diff. Either
  push everything in one go, or gate auto-merge on a manual "ready"
  label after final push.
  - **Stacked-PR variant (#493/#494/#495, 2026-07-31)** — three PRs
    based on each other were all marked ready at once. `auto-merge.yml`
    fires on `ready_for_review` for every non-draft PR, so each merged
    into *its own base* rather than upward: only the bottom one reached
    master and the other two landed in branches that were already
    orphaned. Nothing was lost (relanded by cherry-pick in #496), but
    the rule is: in a stack, only the bottom PR leaves draft: promote
    the next one after its base actually merges. Or don't stack.

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
</content>
