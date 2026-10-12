# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
live plans link to a subplan under `docs/plans/` with the gory
details (shipped subplans are archived under `docs/plans/archive/`).

## Status

**Live in one city.** bite-worthy.com serves Durango: filtered menus, the
chat assistant, scanning, and the admin back office, with the API on
Hetzner deploying itself on every merge. The mobile app builds through EAS
and is not yet in the stores. Phases 0–8 and the legal-remediation arc
(#112–#346) are history in
[`status-archive/roadmap-phases-0-8.md`](status-archive/roadmap-phases-0-8.md)
and `docs/plans/archive/`.

Three kinds of work remain, each with its own section below:

- **Arcs in progress** — multi-city, the MCP pivot's M7, the results pane's P2 and P3, the open follow-ups. Loop-shippable.
- **Launch** — what only a person can do before the app is in the stores. See *Launch* below and [`launch-readiness.md`](launch-readiness.md) for the step-by-step.
- **Growth bets** — the strategy's unscheduled ideas, kept here so the reasoning is not lost with the archived planning docs.

## Multi-city (in progress)

Biteworthy launched as Durango-only; Salt Lake City is next.

- [x] Add cities (admin: `create_city` tool, `/admin/cities`) and add restaurants from the web (`/restaurants/new`); `list_cities` lets the chat find a city with nothing published yet.
- [x] Location URLs: `/restaurants/usa/colorado/durango/<slug>`, computed once in `Restaurant#web_path`, with 301s from every old `/restaurants/<slug>` shape.
- [x] Home city on the profile (`set_home_city`, settings picker): "what's nearby" in chat defaults `search_restaurants` to it. Plan: [`docs/plans/profile-location.md`](plans/profile-location.md).
- [x] Location P2 (web) — "Use my location" in the chat header (moved out of the composer so the input has room on a phone); the device location rides one turn into the tool context (never the prompt, profile, or transcript) and `search_restaurants near_me: true` sorts by distance. Plan: [`docs/plans/profile-location.md`](plans/profile-location.md).
- [ ] Location P2 follow-ups — production count of published addresses with coordinates (backfill if thin), distance in the results pane's `restaurants` kind, mobile `expo-location` behind the same `near_me`.

## Naming standard: no all-caps dishes (shipped 2026-10-11)

- [x] `Names::Standard` — names mostly in capitals become Title Case (acronyms like BBQ/BLT/GF kept, small words lowercase), shouting descriptions become sentence case, footnote asterisks at either end of a name are stripped; deliberate mixed case is untouched. Applied by `normalizes` on `Item` and `IngestionItem`, so every writer gets it.
- [x] Bulk fix for old rows: `bin/rails names:normalize` (dry run unless `DRY_RUN=false`, optional `RESTAURANT_ID`) and the admin tool `normalize_item_names`.
- [ ] Run the production backfill (human: dry run, review, then `DRY_RUN=false`).
- [ ] Decide whether a stripped `*` (the raw/undercooked advisory) should derive the `prep.raw` tag at scan time; today nothing reads it, and the source photo/PDF is the only record once the name is normalized.

## Restaurant branding: logo + banner (shipped 2026-10-11)

- [x] `Restaurant` carries `logo` and `banner` attachments; `Restaurants::Branding` is the one writer (verified owner or admin), every image goes through `Images::StripMetadata`, and only the WebP variants are served (`logo_url` on list/ranking/detail rows, `banner_url` on detail).
- [x] Doors: `PATCH /api/v1/restaurants/:id/branding` (multipart) and the MCP `set_restaurant_branding` tool (attachment ids from `POST /attachments`).
- [x] Chat import: `create_restaurant` takes `logo_attachment_id` / `banner_attachment_id`, and the creator of a draft may brand it until it is published (the scan door's rule), so a restaurant added from chat can be complete without a claim.
- [x] Web `/restaurants/new` form: optional logo and banner pickers; the images go through the branding door right after the create (the creator may brand their draft), with a scan link offered if that upload fails.
- [x] Web: logo on restaurant cards (home, browse, city diet pages) and the page header, banner across the page header; the verified owner edits both from the restaurant page ("Edit logo & banner"), admins from `/admin/restaurants/[id]`.
- [x] Shapes the chat knows and can crop to: logo 1:1 up to 400×400, banner 8:3 up to 1600×600. `Images::Fit` crops each upload to its slot (center, an `anchor`, or a fractional box) and never enlarges; `inspect_image` gives the chat an upload's size, and `set_restaurant_branding` / the REST door take `logo_crop` / `banner_crop`.
- [ ] Web branding editor — crop controls that send `logo_crop` / `banner_crop` (the API takes them; the editor still uploads and lets the server center-crop).
- [x] Mobile — logo on home rows and beside the name on `restaurants/[id]`, banner across the top of that screen (`expo-image`); nothing renders for a restaurant without them.

## Uploads: bigger files in, smaller files stored (shipped 2026-10-10)

- [x] Web scan uploads go straight to the API with a 10-minute ticket (`POST /api/v1/attachments/ticket`, `X-Upload-Ticket`), so the web server's 4.5 MB body limit no longer caps them; the client ceiling is the API's 15 MB.
- [x] A PDF over the 10 MB scan limit, up to 15 MB, gets one Ghostscript `/ebook` pass (`Pdfs::Shrink`) at the attachments door before being refused.
- [x] `Images::StripMetadata` accepts up to 15 MB raw (was 5 MB, the stored cap) and shrinks the stored copy under 5 MB.
- [x] Mobile resizes a picked photo to 2000px JPEG before uploading (`lib/shrink-image.ts`, `expo-image-manipulator`), mirroring web.
- [ ] Review and dish-photo uploads on web still go through the proxy at 4 MB; move them to the ticket path if the client-side shrink ever proves insufficient.

## Profile: about + chat notes (shipped 2026-10-06)

- [x] Public bio — `users.bio` (300 chars, plain text), edited under Public profile in settings via `PATCH /me`, shown on `/u/<handle>`, included in the account export.
- [x] Chat notes — `user_profiles.chat_notes` (500 chars, private), edited under "Notes for the assistant" in settings via `PATCH /profile`, fenced into the chat prompt's caller section as data the filter never reads (kept out of tool results, which are stored), and included in the account export. The privacy page now says the chat sends the profile and notes to Anthropic.
- [x] Mobile — Settings → Account edits the bio and the chat notes, and `users/[handle]` shows the bio.

## MVP speed + UI pass (shipped 2026-09-27, #695–#707)

The core loop — scan a menu, see what you can eat, see your best picks —
made fast and obvious: a REST scan door and web scan screen (photo/link →
review → filtered menu, no chat round per status check), a leaner menu read
path, picks from favorites and ratings without the taste quiz, a filtered
menu before signup (presets and share links *add to* a signed-in user's own
avoids), a menu page that leads with best bets, analytics limited to named
events and scrubbed page views, and throttling per user / real visitor IP.
Dropped as unneeded once measured: extraction retries (the client already
retries), a menu cache, mobile list virtualization. Per-PR detail lives in
`docs/status.md` (2026-09-26 → 27).

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
- [x] Website-seed import — ToS-safe host policy, `discover_restaurant_site`, `create_restaurant` website/phone/hours, `clone_menu` for sibling locations. Plan notes in [`docs/mcp.md`](mcp.md) §ingestion.
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

## Chat results pane (active, 2026-09-29)

The chat stops being a transcript on its own. Beside it sits a pane that
shows what the assistant is acting on — the menu it just read, the scan
it started and the dishes that came out — rendered from the same REST
payloads the pages use. The server sends a small typed reference
(`Tools::Base.pane`, the `pane` event, `conversations.last_pane`); the
web fetches the detail. Read-only until P3.

**Plan + decisions: [`docs/plans/chat-results-pane.md`](plans/chat-results-pane.md).**

- [x] P1 — contract + shell: `pane` hook, `menu` + `scan` kinds, split view on `/chat`
- [ ] P2 — more kinds (restaurants, restaurant, profile, item) + highlight what the last write touched
- [ ] P3 — the pane talks back: dish as page context, accept/reject from the pane, preload from a restaurant page

M1 extracted the menu filter out of `ItemsController` into `Menus::Filter` /
`Menus::Labels` / `Menus::Query` so the `get_menu` tool and the REST endpoint
share one implementation — that logic is the product's safety story and must
not exist twice.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Launch gates** are human work and live in the *Launch* section below;
`docs/launch-readiness.md` is the step-by-step.

1. **[BLOCKED] Store submission — binary assets + screenshot routes + EAS submit** (follow-up to #180). Needs the Apple Developer and Google Play accounts, the L1 sign-off on `/privacy` and `/terms`, and a designed `icon-source.svg`. See *Launch*.
2. ~~**A bot-merged `apps/api` PR does not deploy — dispatch `deploy-api` by hand.**~~ **RESOLVED 2026-08-09; verified 2026-08-14.** The `AUTOMERGE_TOKEN` secret exists, so `auto-merge.yml` no longer merges with `GITHUB_TOKEN` and GitHub's recursion guard no longer swallows the run. Evidence: tonight's auto-merged `apps/api` PRs (#608, #610, #611) all show `merged_by=wbwSoftware` rather than `github-actions[bot]` — the exact check this item prescribed — and `deploy-api.yml` fired `on: push` for each, all successful. No hand-dispatch needed. **Kept in the queue rather than deleted, because it can come back:** `AUTOMERGE_TOKEN` is a fine-grained PAT, and `auto-merge.yml` reads `secrets.AUTOMERGE_TOKEN || secrets.GITHUB_TOKEN` — and those two words hide two *different* failure modes. **Secret deleted:** the expression picks `GITHUB_TOKEN` and the original bug returns silently, master looking shipped while the box is stale. **Secret still set but the PAT expired or was revoked:** `||` tests whether the value is empty, not whether it works, so it yields the dead token and the auto-merge step fails auth instead — PRs simply stop merging, which is at least visible as a red `enable` check. Diagnostic worth not relearning — check `merged_by` on a recently auto-merged `apps/api` PR; `github-actions[bot]` means the token is gone and API changes have stopped shipping. (The GHCR PAT in `.kamal/secrets` expired on 2026-10-12 and did exactly that, loudly: three deploys denied at `docker login ghcr.io`. `deploy-api.yml` logs in with its own `GITHUB_TOKEN` since that day, so the PAT now matters only for laptop deploys.)

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

Loop-shippable work that is not on a shipped arc: M7 (MCP pivot), P2 and
P3 (results pane), the Location P2 follow-ups, the branding crop editor,
the mobile dish-photo upload, and the *Open follow-ups* below. Pick the
smallest one whose plan has acceptance criteria.

## Diner dish photos (shipped 2026-10-06)

- [x] Diners submit a photo of a dish; admins approve before it becomes `Item#photo` (an admin's own upload is approved on submit). Web UI on the dish page and photo-less menu cards, review-form opt-in, `/admin/photos` queue, MCP `list_photo_submissions` / `moderate_photo_submission`, EXIF/GPS stripped. Attribution: "Photo by \<display name\>".
- [ ] Mobile (Expo) — same upload + credit on the dish screen; left as a follow-up.
- [x] Chat: attach a photo and name the dish. `submit_dish_photo` queues it for a moderator after the user confirms they took it; `set_item_photo` puts it live for the verified owner or an admin. No client change: both chats already pass uploads as attachment ids (not exercised end-to-end on a device).

## Open follow-ups

Loop-surfaced tasks that don't belong to a shipped phase. Humans triage
these into the launch path or a future phase. (Resolved follow-ups are
in the [roadmap history](status-archive/roadmap-phases-0-8.md).)

- **Read the hidden-wheat shadow and decide (2026-10-11)** — after a
  few dozen scans, `JevObservation.where(kind: "hidden_wheat_shadow")`:
  if `jev_only` disagreements are real misses (a battered fish with no
  wheat row), let a Jev "yes" add a cautionary `grain-wheat-*` row as
  `inferred`, never remove one; if they are noise, remove the trial and
  the `JEV_WHEAT_SHADOW` switch. `docs/ingestion.md` §2b.
- **Backfill cuisine tags with Jev, or let an admin re-run a menu
  (2026-10-10)** — Jev decides cuisine only for gap items in new runs.
  Every restaurant published before 2026-10-10 still carries Haiku's
  cuisine tags (the shadow trial showed them force-fitting dishes into
  the seven leaf cuisines), and fully matched dishes never got one at
  all. The admin tool `retag_cuisine` (shipped 2026-10-10, backed by
  `Ingestion::JevCuisineRetag`) re-tags one restaurant on demand, with
  `dry_run`. The first dry runs (ten Durango restaurants, 2026-10-10)
  showed Jev refusing the force-fits with nowhere else to put a dish, so
  the cuisine taxonomy grew from 7 to 23 leaves the same day. **Still
  open:** re-run the dry runs on the new taxonomy, then the real runs
  restaurant by restaurant from an admin session.
- **A streamed chat turn gets no retry at all (2026-08-20)** — surfaced
  while making the chat's upstream failures explain themselves
  (`Chat::UpstreamError`). `AnthropicClient#messages_stream` deliberately
  skips the faraday-retry middleware, and its header gives the reason:
  the retry replays the whole request, and a mid-stream failure has
  already put half an answer on someone's screen. That argument holds
  only *after* the first byte. A 429 or 529 that arrives as the response
  status has streamed nothing, and today it ends the turn on the first
  try where `messages_create` would have made three — which is the most
  likely reason a person sees the chat "stop working" at all, since
  overload is the common upstream failure and it is transient by
  definition. The shape is a retry gated on `stream.complete? == false &&
  nothing emitted yet`, not the blanket middleware. Better error copy
  ships in the meantime; it explains the failure rather than avoiding it.
- **Mobile menu-card parity (2026-08-17)** — the web compact-cards pass
  (kill the review-CTA wall, name links to the dish page, suppress the
  lone "Other" heading) deliberately did not touch mobile. Mobile's
  `_ItemRow` still shows "Be the first to review" per card and that CTA
  is the *only* tap target into the dish page — so any mirroring of the
  web change must also make the dish name pressable, or items become
  unreachable. Candidate for a shared filter-engine heading/label helper
  so the two clients can't drift (`groupItemsBySection` mints the
  "Other" fallback both render).
- **`needing_attention`'s empty-payload proxy degraded by implied bases
  (2026-08-17)** — the scope (`ingestion_item.rb`) treats
  `ingredients_payload = []` as "nothing resolved, the filter would be
  empty or wrong for this dish". #638's implied-base pass can now leave a
  composed dish whose explicit matching found *nothing* with a single
  `source: "derived"` row (the inferred wheat), so it no longer trips the
  proxy and skips the attention queue even though a human should still
  look. The honest check is probably "no row with `source: match`"
  (jsonb containment), but that widens a scope several tools read —
  deliberately not folded into #638.
- **Mobile `/settings/analytics` is an orphan route (2026-08-16)** — the
  screen exists (`apps/mobile/app/settings/analytics.tsx`, the analytics
  opt-in switch) but nothing in the app navigates to it; the only
  references are prose comments. Surfaced while placing the version line
  for #624. Needs either a settings/about hub linked from home, or a
  direct entry point — a privacy-relevant control shouldn't be reachable
  only by deep link.
- **User-exploration findings (2026-08-15)** — a live-product walkthrough
  left a severity-ordered findings brief with a small-fixes checklist in
  [`plans/archive/ux-exploration-2026-08-15.md`](plans/archive/ux-exploration-2026-08-15.md) (archived 2026-10-12).
  The checklist items are loop-shippable (several PRs already in flight,
  tracked in the doc). **2026-08-17 demo-readiness push:** of the four
  bigger findings, three shipped — finding 1 (ingestion `gap?` widening,
  #638: a name-keyword implied-bases pass in `DeterministicResolver`
  plus composed-dish routing to a now-sliced gap-fill, gated by the one
  `Ingestion::DietClaims` rule; the live gluten false negatives were
  separately hand-patched via admin edit), finding 3 (the item-page
  ingredients panel), and finding 4 (anonymous scan entry via
  login-bounce linking: scan tile + always-visible Chat nav → `/chat`,
  which bounces signed-out visitors to `/login?next=%2Fchat`
  server-side). Remaining from this set: the confirmation backlog (one
  armed "Confirm community menu" click per restaurant at
  `/admin/restaurants/<id>` — deliberately left to a human because it
  loosens what strict mode shows).

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
  enabled on the first sha and squashed without the second diff. Resolved in
  practice: open as a draft until review is clean, then mark ready.
  - **Stacked-PR variant (#493/#494/#495, 2026-07-31)** — three PRs
    based on each other were all marked ready at once. `auto-merge.yml`
    fires on `ready_for_review` for every non-draft PR, so each merged
    into *its own base* rather than upward: only the bottom one reached
    master and the other two landed in branches that were already
    orphaned. Nothing was lost (relanded by cherry-pick in #496), but
    the rule is: in a stack, only the bottom PR leaves draft: promote
    the next one after its base actually merges. Or don't stack.

## Launch (human-gated)

What stands between the product as it runs today and the app in the
stores. Nothing here is loop-shippable; the step-by-step with commands is
[`launch-readiness.md`](launch-readiness.md). Folded in from the archived
2026 planning docs on 2026-10-12, with everything they listed as open and
the log says has since shipped removed (the first deploy, Resend, R2,
Vercel, PostHog, the ingestion cassette, the Durango seed, the anonymous
filter picker, diet forwarded from the city pages, per-user throttling).

- [ ] **L1 — attorney sign-off on `/privacy` and `/terms`**, with the chat-privacy brief ([`plans/chat-privacy-l1-brief.md`](plans/chat-privacy-l1-brief.md)) and the L3 ruling on auto-cropping third-party dish photos. Long lead; blocks store submission. The DRAFT banners already came off at the owner's call (2026-10-05/06). Gates in [`plans/legal-remediation-followups.md`](plans/legal-remediation-followups.md).
- [ ] **L2 — register the DMCA designated agent** (~$6) and the repeat-infringer process behind `/dmca`.
- [ ] **Apple Developer ($99/yr) and Google Play Console ($25)**; then the three `REPLACE_WITH_…` placeholders in `apps/mobile/eas.json`, the gitignored `play-service-account.json`, and note the **Apple Team ID and Android signing SHA-256** for deep links later.
- [ ] **Design `icon-source.svg`**, render the binary assets (`pnpm mobile render:assets`), wire screenshot routes, `eas build` then `eas submit`. Apple review 1–7 days.
- [ ] **Neon snapshots.** ADR 0007 admits the database has no backup beyond Neon's own; one wipe during early word of mouth is unrecoverable. Turn on point-in-time restore or a scheduled export before inviting more people.
- [ ] **Error reports to a private GitHub repo** — pick the repo, mint the fine-grained token, add `GITHUB_ERROR_REPORTS_TOKEN` and `GITHUB_ERROR_REPORTS_REPO` to the deploy (`launch-readiness.md` §11). Until then failures are counted in `error_reports` and PostHog but no issue is filed.
- [ ] **Check strict-mode `visible_count` on the live data** before a wider push: the safest users must see real options, or honest disclosure is failing the people it exists for.
- [ ] **Production backfills waiting on a person:** `names:normalize` (dry run, review, apply) and the Jev cuisine re-tag runs, both listed above.
- [ ] **Press outreach** from [`outreach/`](outreach/), seven days before a public launch; stage `launch-day.md`.

## Growth bets (from the 2026 strategy, not scheduled)

The mid-2026 strategic review (archived under
[`archive/strategy-2026/`](archive/strategy-2026/)) diagnosed a
**high-value, low-frequency** product and bet on three things: coverage
through anyone-can-scan (shipped), frequency through a contribution
identity, and reach through taste discovery, with consumer freemium as the
model. Its standing decisions and the work it left unscheduled:

**Standing decisions.** Keep the safety-first headline ("see only what you
can eat") and ship discovery only as a Top Picks layer inside already-safe
menus; flip the headline to "what should I order?" only when **Top Pick
acceptance clears about 30%** with the safety numbers green. Never let
marketing say "safe". Expand to a second city only with a vandalism gate
in place and the week-2 return rate trending up. The three numbers on the
wall: **week-2 return rate** (≥ ~15%), **coverage velocity** (menus added
per week by users), and **strict-mode `visible_count`**.

- [ ] **Instrument the two decision metrics.** Week-2 return rate (derived in PostHog from `app_open`) and Top Pick acceptance: `packages/analytics` has no tap-or-save event for a pick yet.
- [ ] **Contribution identity on `/u/<handle>`** — confirmations count, "menus you keep accurate", city rank. The confirm-and-dispute loop it builds on exists in part: dish verification shipped in #838 (two levels, verifier attribution). Build the identity only once verification shows repeat use.
- [ ] **Anonymous onboarding** — the avoid list as a `profile_token` in the browser, applied across restaurants, "save to account" offered afterwards. Today `/onboarding` still bounces a signed-out visitor to `/login`; the anonymous presets and share links shipped 2026-09-26 cover the first visit, not a custom list.
- [ ] **Visibility** — the sitemap still lists only the static pages and `/durango/<diet>` (the `restaurantPaths` hook in `apps/web/src/lib/sitemap.ts` is unfilled); restaurant pages have `generateMetadata` but no Restaurant or Menu JSON-LD; share links and `/u/<handle>` have no Open Graph unfurl.
- [ ] **Restaurant QR program** — phase 1 encodes the restaurant's share URL for a table tent (web-only, small); phase 2 deep-links into the app (`associatedDomains`, `intentFilters`, AASA and assetlinks) and needs the Team ID and signing SHA from the store accounts. The read path is already anonymous, so this is mostly image generation and an admin action.
- [ ] **Taste quiz and starter taste profiles** — [`plans/taste-quiz.md`](plans/taste-quiz.md) is the spec; the scoring engine exists (`TasteScoring`), onboarding is dietary-first and taste is a skippable step. Gated on the acceptance metric above.
- [ ] **Vandalism gate before city #2** — trusted-contributor weighting on community publishing (two independent verifiers, or one trusted, for auto-publish). Salt Lake City is next in *Multi-city*, so this moves up when that opens to the public.
- [ ] **Array-sync guardrail** — a nightly reconciliation that `items.ingredient_ids` and `items.tag_ids` equal their join rows, alerting on drift. The callbacks keep them in sync today; nothing checks after the fact.
- [ ] **Freemium and billing** — free = N scans a month plus filtering; premium (~$20–30/yr) = unlimited scans, multiple profiles (household), strict mode, offline, and **table/group mode** ("what should the four of us order?"). Needs App Store and Play billing or Stripe; a manual setup item when it comes.
- [ ] **Shared throttle store** — Rack::Attack counts per process; move to a shared store before the API runs more than one process ([`plans/legal-remediation-followups.md`](plans/legal-remediation-followups.md) F4).
- [ ] **The Yuka "activism" lever** — let diners push a restaurant to confirm or correct its own menu. Evaluate after city #2.

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
</content>
