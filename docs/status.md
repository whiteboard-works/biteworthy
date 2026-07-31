# Delivery status log

The autonomous loop's running log. Newest entries on top. One line per
tick or significant event. Format:

```
YYYY-MM-DD HH:MM (UTC) — <summary>
```

The point is breadcrumbs: a tick interrupted at minute 28 should leave
enough here for the next tick (or a human dropping in) to resume
without spelunking GitHub.

Entries from ticks #1–#126 (2026-04-28 → 2026-05-06, Phase 0 through
the Phase 5 pause) are archived in
[`status-archive/2026-04-to-05.md`](status-archive/2026-04-to-05.md).

---

2026-07-31 — Docs truth pass: the headline filter query in `CLAUDE.md` and `docs/schema.md` never existed. Both presented a `WHERE NOT (ingredient_ids && $avoid)` SQL statement as "the entire reason the schema looks the way it does". The real read path is `ItemsController#index` loading EVERY published item at the restaurant and computing `reasons[]` in Ruby — which is correct and load-bearing, because honest disclosure means a hidden item has to survive the query to explain itself. The documented `ORDER BY cardinality(items.tag_ids & $prefer_tags)` could never have run at all: `&` is an `intarray` operator and works on `int[]` only, never `uuid[]`. Ranking is really `TasteScoring` (liked/disliked ± popularity ± avg visible rating); `user_profiles.prefer_tag_ids` is read by NOTHING that sorts, and the matching lie in `filter-engine/src/index.ts` ("only affects sort order (server-side)") is corrected too. Consequence recorded but not acted on here: the GIN indexes on `items.ingredient_ids`/`tag_ids` and the three on `user_profiles` are never exercised — the Ruby path can't use an index and `TasteScoring`'s `unnest(...) WHERE = ANY(...)` can't either. Docs-only; no behavior change. Branch `chore/schema-doc-truth-pass`.

2026-07-31 — Security: cleared every open JS advisory. `pnpm audit --prod` went from 10 vulnerabilities (7 high) to zero via `pnpm.overrides` — the pattern this repo already used for esbuild/postcss/vite. All eight were TRANSITIVE (nothing we depend on directly): sharp←next, shell-quote←react-native, brace-expansion+js-yaml←expo-router, uuid←expo, plus form-data/undici. Two needed cross-major jumps with no in-major backport (`brace-expansion` ≤5.0.7 is ALL of v1/v2, `uuid` <11.1.1) — checked first that both ship dual CJS/ESM builds so `require()` still resolves, then verified empirically: 734 tests across web/mobile/filter-engine, typecheck, lint, and a real `next build` all pass. Version-scoped keys (`js-yaml@3`, `js-yaml@4`) keep each major on its own patched line. Separately: the 14 `_legacy/Gemfile.lock` alerts are noise — `_legacy` appears in no Dockerfile or deploy config, only as a CodeQL path filter, and CLAUDE.md forbids editing it. Two pre-existing problems found while verifying, NOT caused by this change and NOT fixed here: (1) `pnpm --filter @biteworthy/mobile build` fails on master too — `@expo/metro-runtime` won't resolve under pnpm's layout; CI never runs `pnpm build` so it went unnoticed. (2) `ci-js.yml` and `ci-api.yml` both cancel in-flight runs on push, and a cancelled required check reads as neither success nor skipped — so a rebased dependabot PR sits BLOCKED until someone re-runs it by hand. Branch `chore/security-updates`.

2026-07-31 — Add-on editing in the verify flow, closing the last gap in "fix it as far upstream as possible". Purely a web change — the API already permitted `addons_payload` in `edit_params` and documented the row shape in rswag; only the panel couldn't reach it, so add-ons were display-only and a misread one had to be corrected on the LIVE menu after promote. The panel now edits name + price, adds and removes rows, and carries `source` through untouched so an extractor-found add-on stays attributable. A named add-on with no price is kept (plenty are free) and travels as `price_cents: null`; only a wholly blank row is dropped — the same rule the item panel applies to variants. A priced add-on with no NAME blocks the save instead, because promote skips nameless rows and saving one would quietly lose the price — the offending row's name input is flagged so it's findable. (Note the sibling `pricesToPayload` in the same file still has the opposite, older behavior: it silently drops a price row with a size but no amount. Left alone deliberately — fixing it means changing promote too, since `create_variants!` also drops priceless rows.) `kind` is not editable here: the staged payload has no kind and promote hardcodes `"addition"`, so choice/side is a post-promote distinction made in the admin item panel. Review caught the important one: `apply_update!` leaves modifiers alone on matched re-scan cards, so an add-on editor there would take a correction, report success, and change nothing live — the editor is now HIDDEN on matched cards, the append-note says name and add-ons aren't applied, and the add-on blockers are suppressed there so extractor junk can't strand a card the verifier never touched. Branch `feature/verify-addon-edits`.

2026-07-31 — Split-shift hours. A day may now carry SEVERAL ranges: lunch 11–14 + dinner 17–21 is an ordinary restaurant week, and the old one-row-per-day rule forced it into a single 11–21 row that advertised the kitchen as open through the afternoon lull. No migration needed — `hours` never had a unique index on `(restaurant_id, day_of_week)`; only the E5 controller enforced it. The `duplicate_day_of_week` 422 is replaced by the narrower `closed_day_has_hours` (a day can't carry both a blank "closed" row and a timed one — nothing downstream could pick a winner); identical repeated rows collapse instead of erroring. The place endpoint orders `(day_of_week, opens_at)` so ranges come back in the order they're worked, and the hours grid grows a "+ Split shift" control per day. Nothing outside the admin place endpoint reads `hours` yet, so blast radius was one controller + one component. Review caught the trap this opened: "+ Split shift" creates an EMPTY range, and sending it beside a real one reads as "closed AND open" — so two clicks failed the whole week's save with copy telling the admin to untick a box that wasn't ticked. Empty ranges are now dropped before the payload (a half-filled one is real input and still travels), matching how the item panel treats empty variant rows. Known gap, deferred: no overlap guard, so a day can hold contradictory ranges — inert until something public renders hours. Branch `feature/split-shift-hours`.

2026-07-31 — Upstream-editing follow-ups from the E4/E6 reviews. Contract change worth knowing: `PATCH /admin/items/:id` now KEEPS a variant row that carries a size but no price ("Large — market price"). It used to drop them, which meant an admin fixing a typo on one row silently deleted any size-only sibling — and re-scan produces those, since `IngestionItem#apply_update!` passes `price_cents` through with no blank guard. Only a wholly empty row is dropped now, matching how modifiers already behaved. (The INGESTION `prices_payload` still drops priceless rows at promote — that path is unchanged.) Also: the place editor refused to save before its GET resolved (both saves are wholesale replaces, so clicking Save over the still-empty form destroyed the real week and blanked the address), hours moved to `<input type="time">` so a typo can't reach the server, an open day left blank no longer vanishes from the payload, admin item `description` clears to NULL rather than `""`, variant `currency` round-trips instead of being rewritten to USD, and `AdminItemEdits` now derives from the generated contract (which immediately caught the status select widening the enum to `string`). Branches `feature/admin-item-panel`, `feature/admin-structure-ui`, `fix/admin-editor-followups`.

2026-07-31 — Upstream-editing workstream E2: verify-flow item editing (web). `_ItemEditPanel` gives every staged dish an inline editor — name, description, ingredient/tag chips (× to remove, taxonomy search to add: ingredients via the public `?q=` endpoint, tags fetched once and filtered locally since that endpoint has no search) and price rows edited in dollars, sent as cents. "Save edit" records corrections without promoting; Accept with the panel open applies them first. An untouched row still sends NO edit keys — resending stale payloads would wipe gap-fill's later appends. Matched (re-scan) cards carry a note that edits only shape what gets ADDED. `decideRunItem` widened to `'edited'` + an `edits` object (mirrors mobile's shape). The admin run review inherits all of it — same row component. Branch `feature/verify-item-edits`.
2026-07-31 — Upstream-editing workstream E6: admin structure + place editors (closes the workstream). The restaurant workbench gains a menu manager (create/rename menus + sections inline, per-section dish counts, delete behind the two-step confirm) and a place editor (address form + a 7-day hours grid with a Closed toggle per day). Two shapes mirror the API: hours submit the WHOLE week every time (a half-applied save would advertise the wrong opening time; Closed sends explicit nulls), and section deletes report how many dishes were kept — restructuring never destroys dishes, and the confirm copy says so. The menu tree also feeds the item rows' section select, so E4's "move a dish between sections" is now reachable. Branch `feature/admin-structure-ui`.

2026-07-31 — Upstream-editing workstream E4: admin item deep-edit panel. Each item row in the restaurant workbench opens an editor for name, description, ingredient/tag chips (× to remove, taxonomy search to add), prices, add-ons/options (name + kind + price), and section. Same discipline as the verify editor: only CHANGED facets are sent, since slug lists and the variant/modifier arrays replace wholesale server-side. Structured refusals become instructions — an unknown slug names the offender and points at Taxonomy, a foreign section says so. The row now shows ingredient/tag NAMES instead of bare counts. The section select stays hidden until E6 supplies the menu tree. Also adds `menu_section_id` to the admin item rswag schema (the controller already served it). Branch `feature/admin-item-panel`.

2026-07-31 — Upstream-editing workstream E3: admin item deep-edit. `PATCH /api/v1/admin/items/:id` grows the fields an admin needs to fix a LIVE dish: `ingredient_slugs`/`tag_slugs` (join sync), `variants` + `modifiers` (wholesale replace, array order = position), and `menu_section_id` (same-restaurant guard → 422 `foreign_menu_section`). Logic lives in `Admin::ItemEditor`: new joins land `confirmed`/`human` (an admin IS the trusted source — same convention as SuggestionResolver), removals go row-by-row so the denormalized `items.ingredient_ids`/`tag_ids` the filter query reads stay honest, and an unknown slug 422s with the offenders instead of the promote path's silent skip. `confidence` and the id arrays stay unreachable. Serializer now returns ingredient/tag NAMES + modifiers (sorted in Ruby, so the index's preloads aren't discarded by an ORDER BY). Variant prices carry the same non-negative-integer floor the staged path enforces — this endpoint writes to an ALREADY-published menu. Test note worth remembering: `item.ingredient_ids` in Ruby is the has_many-through reader and SHADOWS the denormalized column the filter query reads, so the P0 spec asserts `read_attribute(:ingredient_ids)` and re-runs the filter predicate; mutation-checked by swapping `destroy!` for `delete`. Gotcha for future admin services: inside `Api::V1::Admin`, a bare `Admin::Foo` resolves to `Api::V1::Admin::Foo` — reference it as `::Admin::ItemEditor`. Branch `feature/admin-item-deep-edit`.
2026-07-31 — Upstream-editing workstream E5: admin restaurant structure API. Menus + sections CRUD (`/admin/restaurants/:id/menus`, `/admin/menus/:id`, `/admin/menus/:menu_id/menu_sections`, `/admin/menu_sections/:id`) and place data (`GET /admin/restaurants/:id/place`, `PUT …/address`, `PUT …/hours`). Two deliberate shapes: hours are a WHOLESALE week replace (a per-day endpoint could land half-applied and advertise wrong hours; blank times = closed, 422 on a day outside 0-6), and address is create-or-replace since a restaurant has one in practice. Restructuring never destroys dishes — deleting a section unsections its items (reported as `items_unsectioned`), deleting a menu takes its sections but leaves the items. Branch `feature/admin-restaurant-structure`.

2026-07-31 — Upstream-editing workstream E1: staged items accept full edits. `prices_payload` joins the verify PATCH's permitted fields (`[:size, :price_cents]`) — a verifier can now fix a misread price before promote materializes ItemVariants, instead of correcting the live menu after. rswag payload schemas tightened from `additionalProperties: true` to real row shapes (slug-required ingredient/tag rows, nullable size/price), so the generated TS carries them. Specs pin: edited prices beat extracted ones on create-accept, `[]` clears while an omitted key leaves the column alone, edited prices replace variants on a matched card, and dropping a chip from a matched card still does NOT remove it from the live item (append-only contract intact). Branch `feature/staged-item-price-edits`.

2026-07-30 — Web-admin workstream F1: Avo retired. Deleted the avo gem, all 17 resources + 7 actions + 4 filters + generated controllers, the initializer + `mount_avo`, the ERB `/admin/dashboard` (controller + views), the Avo smoke/dashboard/action specs (their assertions live on in model + request specs — verified before deleting), and the `basicAuth` securityScheme (openapi + api-types regenerated). `ADMIN_USERNAME`/`ADMIN_PASSWORD` removed from deploy.yml, .env.example, .kamal/secrets.example, and docs; the web /admin (is_admin-gated) is now the only admin surface. Full API suite green post-deletion. Branch `chore/retire-avo`. MANUAL: remove ADMIN_USERNAME/ADMIN_PASSWORD from the live Kamal secrets.

2026-07-30 — Web-admin workstream W6: /admin/restaurants + /admin/users. Restaurants list (search, status + community_published filters, "N awaiting graduation" badges) → per-restaurant workbench: field/status form (publish/unpublish/close), confirm-community with graduated counts, and an all-statuses item list whose status select is the per-dish unpublish (`removed`); confidence renders as a badge, never editable. Users page: search, admin-only filter, promote/demote behind the two-step confirm with the self-demotion refusal mapped to instructions. Avo parity reached — every Avo workflow now has a web /admin home; F1 (retire Avo) is next. Branch `feature/admin-management-ui`.

2026-07-30 — Web-admin workstream A5: admin restaurant/item/user management API. Restaurants index/show/update (q/status/community_published/city filters, suggested-items "needs graduation" counts, per-confidence detail counts; slug immutable, status writes through the model enum), admin items index (ALL statuses, unlike the public published-only endpoint) + PATCH name/description/status — `status: removed` is the admin unpublish and the first real writer of that lifecycle value, with a request-spec pin that a removed item vanishes from the public menu; confidence + denormalized arrays deliberately not accepted. Users index/search + `is_admin` toggle with the self-demotion 422 guard (system can't reach zero admins). Branch `feature/admin-management`.

2026-07-30 — Web-admin workstream W5: /admin/taxonomy editor. Ingredients + tags pages with inline row editing (mutable fields only — slug/path/family never rendered as inputs since the server 422s them), create forms with alias splitting + family select, name/alias search + family filter, delete behind the two-step confirm with 409 reference counts rendered as "Still referenced — N items, …". Deviation from the plan file: inline row editing instead of separate [id] edit routes (2 pages instead of 6 for the same capability). `lib/admin/shared.ts` gains patchAdminJson/deleteAdmin + AdminError.body. Branch `feature/admin-taxonomy-ui`.

2026-07-30 — Web-admin workstream A4: admin taxonomy CRUD. `/api/v1/admin/{ingredients,tags}` index/create/update/destroy — the catalog's first HTTP write path (previously Avo-only). Safety rails are the feature: slug/path (+tag family) immutable post-create (422 `immutable_field` — slug renames silently drop joins at promote time, path renames orphan ltree descendants), parent-must-exist on dotted paths, destroy refused 409 `in_use` with per-source counts (descendants `<@` excluding self / item joins / dietary presets / profile avoid+taste arrays). Merge + subtree rename explicitly v2. Branch `feature/admin-taxonomy`.

2026-07-30 — Web-admin workstream W4: /admin/reviews + /admin/suggestions queues. Reviews page defaults to the flagged tab (visibility pills: flagged/hidden/visible/all), per-row reason picker + Hide (server-returned row swap, never optimistic) and Unhide; suggestions page is the cross-restaurant pending queue reusing `decideSuggestion` from the owner queue — decided rows leave the list, failures keep the row + inline error. `postAdminJson` grew a JSON body param for hide's `{reason}`. Branch `feature/admin-moderation-ui`.

2026-07-30 — Web-admin workstream A3: admin review + suggestion moderation API. `GET /api/v1/admin/reviews` (visibility=flagged default → `awaiting_moderation` scope; hidden/visible/all; item/user filters), `POST …/:id/hide` (reason ∈ HIDDEN_REASONS, 422 otherwise — "mark spam" is hide with reason spam, no extra endpoint) + `unhide`; `GET /api/v1/admin/suggestions` (cross-restaurant pending queue, oldest-first; accept/reject reuses existing `PATCH /suggestions/:id`, now rswag-documented). Suggestion serialization extracted to a `SuggestionPayload` concern shared with the owner queue. Branch `feature/admin-review-moderation`.

2026-07-30 — Web-admin workstream W3: /admin/runs moderation UI. Queue page (community-only default, status filter, URL-backed deep links, decision-count triage rows) + per-run review page that reuses the verify machinery verbatim (`VerifyItemRow` + `lib/ingestion.ts` — the endpoints are creator-or-admin gated; admin accepts land `confirmed` server-side) and adds the two admin levers: re-extract (mapped refusal copy for `already_published`/`has_promoted_items`) and confirm-community (reports flipped counts). New shared `_ConfirmButton` (two-step inline, replaces window.alert precedent) + `_Pagination`; `AdminError` now carries the Rails error code. Branch `feature/admin-runs-ui`.

2026-07-30 — Web-admin workstream A2: admin ingestion moderation API. Cross-user runs queue `GET /api/v1/admin/ingestion_runs` (status/community/restaurant filters, user+restaurant refs, per-run decision counts via one grouped query), `POST …/:id/re_extract` (logic extracted to `Ingestion::ReExtractRun`, shared with the Avo action; 422 on published), `POST /api/v1/admin/restaurants/:id/confirm_community` (returns flipped counts). Also documents the four existing verify endpoints (run show, items index/PATCH/accept_all) with rswag + shared `IngestionItemPayload`/`IngestionRunPayload`/`Pagination` schemas — partially closes the "ingestion endpoints lack rswag specs" follow-up (multipart `POST /ingestion_runs` + `POST /restaurants` still undocumented). Confirmed-vs-suggested promote pin already existed at request level (`ingestion_items_api_spec.rb`). Branch `feature/admin-ingestion-moderation`.

2026-07-30 — Web-admin workstream W2: /admin ops dashboard. Stat tiles off `GET /api/v1/admin/dashboard` (A1): community spend today vs the 503-guard ceiling (warn badge ≥80%, "scans paused" at 100%), per-period cost/latency/cache tiles with an "Over cost target" flag, moderation queue counts. New plumbing: `adminProxy` (proxyAuthed + `Cache-Control: no-store` — relayUpstream never set cache headers) and the `src/lib/admin/` data layer (`AdminError` + `getAdminJson` + `friendlyAdminError`; single error class for the surface, deliberate deviation from per-domain error subclasses). Dashboard payload typed from the generated OpenAPI types. Branch `feature/admin-web-dashboard`.

2026-07-30 — Web-admin workstream W1: /admin shell + guard. Server layout guard (`apps/web/src/app/admin/layout.tsx`): signed-out → `/login?next=/admin`, anyone not confirmed admin via Rails `/me` → standard 404 (fail-closed on API error/skew, `force-dynamic`, noindex); shared `jwtIsAdmin` in `src/lib/admin-auth.ts`; `GET /api/auth/admin` header probe (fails safe to `false` — opposite of onboarded, deliberately); SiteHeader Admin link resolves once per sign-in (not per nav — avoids a per-route Rails round-trip for non-admins); robots.txt `Disallow: /admin`. Deviation from the plan file: `adminProxy` + `lib/admin/shared.ts` deferred to W2 (first consumer). Branch `feature/admin-web-shell`.

2026-07-30 — Web-admin workstream A1: admin auth foundation. New `Api::V1::Admin::BaseController` (`require_admin!` → unrevealing 404, matching the owner-or-404 precedent), `GET /api/v1/me` (re-reads the payload without `auth/refresh`'s jti rotation), `GET /api/v1/admin/dashboard` (JSON twin of the ERB cost dashboard + queue counts for nav badges), `is_admin` added to `user_payload`/`UserPayload` (required — regenerates web+mobile types, additive), `Biteworthy::AdminRoster` + `admin:grant/revoke/sync` rake tasks (idempotent; never pre-creates users). Kicks off the admin-backoffice workstream (see roadmap): full web /admin in `apps/web`, Avo retired at the end. Branch `feature/admin-auth-foundation`. MANUAL: set `ADMIN_EMAILS` in Kamal secrets + run `bin/rails admin:sync` after deploy.

2026-07-30 — Mobile verify deck renders re-scan update cards: "Updates ‹name›" badge, description/price → diff lines, green `+slug` rows, "✓ Accept update" action; absent `match` field renders today's card (deploy-skew guard). Branch `feature/mobile-rescan-update-cards`. Closes out the re-scan dedup + diff/merge arc (API matching #463, apply #464, web #465).

2026-07-30 — Web verify renders re-scan update cards: amber "Updates ‹name›" badge, strikethrough→new diff for description/prices, green `+slug` chips for added ingredients/tags, "Accept update" button label, "Already on the menu" for no-change matches. Absent `match` field falls back to today's create card (deploy-skew guard). Branch `feature/web-rescan-update-cards`.

2026-07-30 — Re-scan apply-on-accept: accepting a matched card now merges the scan into the existing Item (description/prices refreshed, ingredients/tags append-only, community accepts downgrade confirmed Items to suggested) instead of duplicating; undo restores an `applied_changes` snapshot rather than destroying the live Item. Avo Accept counts "updated" separately. Branch `feature/ingestion-rescan-apply`. Remaining in arc: web + mobile update cards.

2026-07-30 — Re-scan matching ships dark: ResolveItemsJob now links staged items to the restaurant's existing Items (`Ingestion::ExistingItemMatcher` — normalized-token exact, else trgm ≥ 0.60 + token-subset veto; greedy 1:1) and the verify API serializes a `match` block with a serialize-time diff (`Ingestion::ItemUpdateDiff`). Accept still creates (dark) — apply-on-accept is the next PR. Threshold calibrated against live pg_trgm probes: raw similarity cannot separate "Chicken Burrito|Chicken Burrito Bowl" (0.800) from plurals (0.842), hence the subset veto instead of the originally-planned 0.70 raw threshold. Branch `feature/ingestion-rescan-matching`.

2026-07-30 — `promote!` now materializes `prices_payload` as `ItemVariant` rows (size + price_cents, payload order; priceless rows skipped). Previously extracted prices were silently dropped at accept. Branch `fix/promote-prices-item-variants`. First PR of the re-scan dedup + diff/merge arc (matching + apply-update PRs follow).

2026-07-29 — Add-on guard: "Add X for $3" upsell lines no longer stage as dishes. Branch `feature/ingestion-addon-guard`.

- Extraction prompt + schema now classify add-on lines and nest them under the
  parent dish (`addons`); a deterministic materialization backstop folds stray
  top-level `/\Aadd\s/i` items into the previous item's new
  `ingestion_items.addons_payload` (`source: "guard"` vs `"extract"`). Accept
  promotes each row to an `ItemModifier` (`kind: "addition"`) — first writer the
  table has ever had. Verify UIs (web + mobile) render addon sub-rows. v1 is
  name+price only — no ingredient/tag resolution on addons yet; a folded line
  keeps only its first price.
- Live cassette re-recorded in this branch (prompt edit invalidates the request
  match); clients guard `addons_payload` with `?? []` for API deploy skew.

2026-07-29 — Deterministic-first resolve: the two LLM resolve calls are gone. Branch `feature/deterministic-resolve`.

- Owner's call: resolve was slow + over-relied on LLMs — it was asking Haiku to do
  table lookups against data Postgres already indexes. New pipeline: `ResolveItemsJob`
  (pure code — `IngredientMatcher` alias/longest-phrase matching + `TagDeriver`
  per-family strategies; allergen tags ONLY ever derive from ingredient ltree
  ancestry) stages the run in seconds; one background `GapFillResolveJob` Haiku call
  covers only gap items (implied ingredients + cuisine), tracked by
  `ingestion_runs.enrichment_status`, append-only, pending-items-only, soft-fail.
- Deleted: `ResolveStageJob`/`ResolveIngredientsJob`/`ResolveTagsJob` + prompts +
  `ResolutionSchema`. Quick fixes: batched payload writes (upsert_all; NOT NULL
  columns must ride along — PG checks them before ON CONFLICT), AnthropicClient
  open/read timeouts, tags-prompt wording bug retired.
- Payload rows now carry `source: match | derived | ai`. Web + mobile poll through
  `enrichment_status`; docs/ingestion.md rewritten (also fixed two stale claims:
  extraction never carried the taxonomy; trgm re-ingestion dedup remains unbuilt).
- Known trade-off (deliberate): Accept All right after staging promotes with
  explicit-mention data only; gap-fill never mutates decided items.
- Deploy runbook: in-flight runs at `:resolving` hold queued jobs for the deleted
  classes (NameError). Post-deploy: `ResolveItemsJob.perform_later(id)` for
  `IngestionRun.where(status: "resolving")` (idempotent) + clear failed executions.

2026-07-29 — Restaurant menu renders as a photo grid with placeholders. Branch `claude/placeholder-photos-restaurant-grid-rh7ich`.

- The restaurant page (`apps/web/.../restaurants/[slug]`) listed items as a flat
  vertical list; only items with a cropped `photo_url` showed an image, leaving
  photo-less items visually bare. Reworked `ItemRow` into a card (photo on top,
  content below) and switched `SectionBlock`'s visible + hidden lists to a
  responsive grid (`grid-cols-1 sm:2 lg:3`).
- Items with no `photo_url` now get a deterministic monogram placeholder
  (first letter over an id-seeded HSL tint, `role="img"` + aria-label) so the
  grid never has empty photo slots. Real-photo `<img>` contract from Phase
  4.11.4 is unchanged; placeholder uses a distinct testid so the existing
  "no `<img>` when photo_url is null" test still holds.
- Purely presentational — no API/serializer changes. Added placeholder render
  tests; web typecheck + lint clean, 34/34 restaurant tests pass.

2026-07-28 — Web scan menu accepts multiple photos/uploads. Branch `claude/scan-menu-multiple-photos-qnjml8`.

- The web `/ingest` "drop a PDF / photo" section was single-file only, while the
  Rails endpoint (`inputs[]`, capped at `INGESTION_MAX_INPUT_FILES` = 10) and the
  mobile multi-page capture already supported many. Closed the web gap so a whole
  multi-page menu uploads as one run.
- `apps/web/src/lib/ingestion.ts`: `ingestFromFile` now takes `files: File[]` and
  appends each as `inputs[]` (was a single `file`).
- `apps/web/src/app/ingest/page.tsx`: `file` state → `File[]`; file picker gets
  `multiple`; both the camera and picker inputs accumulate (repeat captures + picks
  add pages rather than replace), input value cleared so the same file can re-add;
  removable per-file list; "Upload N files" button label.
- No API/mobile change needed — API + mobile were already multi-input.
- Tests: +1 lib test (multi-file → 2 `inputs[]`), +3 page tests (multiple picker
  files, camera accumulation, single-file removal). Web vitest 238; typecheck/lint green.

2026-07-21 — Account page PR-3: favorites (restaurants + dishes). Branch `feat/account-favorites`.

- Final item of the account-page arc. Users can now save **restaurants and dishes**
  and see them on `/profile/settings`. Two join tables `favorite_restaurants` /
  `favorite_items` (migrations 20260721130000/130001), mirroring `user_item_overrides`
  (presence-of-row = favorited, real FKs, unique (user, target) index).
- API: toggle endpoints `POST/DELETE /api/v1/restaurants/:id/favorite` +
  `/items/:id/favorite` (idempotent, mirror ItemOverridesController); list endpoint
  `GET /api/v1/profile/favorites` (restaurants + items with status). `favorited` flag
  added to `restaurants#show` + `items#show` (authed → seeds the detail-page button).
  Model + request specs; brakeman clean.
- Web: `FavoriteButton` island (optimistic, reverts on error) on the restaurant +
  dish detail pages (SSR-seeded via a JWT-authed fetch, gated on signed-in); account
  page "Favorites" section; proxies + `setItemFavorite`/`setRestaurantFavorite` +
  `fetchMyFavorites`. Hand-written web types (no rswag), matching the history/reviews
  siblings. Web vitest 234 (+7); typecheck/lint green. Account-page arc complete.

2026-07-21 — Account page PR-2: "My reviews" list. Branch `feat/account-my-reviews`.

- Adds a **My reviews** section to `/profile/settings`: the caller's own reviews,
  newest first, each linking back to the dish, with the star rating and — unlike the
  public by-handle feed — the user's **hidden** reviews shown with the moderation
  reason. New authed `GET /api/v1/profile/reviews` (`ProfileReviewsController`,
  paginated, includes hidden own reviews) mirroring `profile/history`'s shape; route
  under the `resource :profile` block. Hand-written web type (`MyReview` in
  `lib/profile.ts`) + `GET /api/profile/reviews` proxy, matching the history/users
  sibling precedent (no rswag — those siblings hand-write too).
- API request spec 5 ex green; web vitest 225 (+2); typecheck/lint green. PR-3
  (favorites: restaurants + dishes) is the remaining item.

2026-07-21 — Account page PR-1: dietary preferences (show + edit). Branch `feat/account-preferences`.

- User-requested rework of `/profile/settings` (the "Account" nav link): it now
  shows **all** dietary preferences with resolved names — diet preset, strictness,
  avoid ingredients/tags, taste love/pass — and edits them in place. Previously
  they could only be set once, in the onboarding wizard.
- API: `GET /api/v1/profile` now returns resolved `{id, slug, name}` rows
  (`avoid_ingredients`, `avoid_tags`, `liked_tags`, …) alongside the raw id arrays
  the mobile/onboarding clients still read. New `IngredientRef`/`TagRef` swagger
  components; openapi + api-types regenerated. Web: added the `GET /api/profile`
  proxy (was PATCH-only) + `lib/profile.ts` (`fetchProfile`/`updateProfile`).
- Each edit is a **partial** PATCH; the load-bearing property (tested) is that
  removing one avoid item submits the *remaining* ids, never a wipe — the endpoint
  replaces each array it receives wholesale. Taste editing links to the existing
  "Improve my picks" flow. Web vitest 223 (+9); typecheck/lint/codegen green.
- Part of a 3-PR arc (favorites = restaurants + dishes, and a "my reviews" list are
  PR-2/PR-3, still to come). ⚠️ Found a local-dev footgun: `apps/api/.env` sets
  `DATABASE_URL` to production Neon, so `RAILS_ENV=test` rails tasks hit prod — ran
  specs against a LOCAL `biteworthy_test` via an explicit localhost `DATABASE_URL`.

2026-07-21 — Verify-flow redesign PR-3: verify page UI. Branch `feat/verify-page-redesign`.

- Surfaces the PR-1/PR-2 backend to users. The verify page now shows dishes from
  `:resolving` on (not just `:staged`), **grouped by sub-menu** (section), each
  row's ingredient/tag chips reading **"matching…"** until enrichment fills them.
  Added **Accept All** (bulk) and **Undo** (per row → un-promote), and publish
  messaging that reflects "finalizes once matching finishes." lib:
  `acceptAllRunItems` + `decideRunItem(pending)`; new `/items/accept_all` proxy;
  `position` on the item payload type.
- Web vitest 214 (+4), typecheck/lint green. Verify-flow redesign (PR-1/2/3) done;
  mobile verify screen mirrors this as a follow-up. Still open: confirm the new
  pipeline with a live scan; the resolve JSON-parse robustness follow-up.

2026-07-21 — Homepage discovery: show restaurants + menu links everywhere.
Branch `feat/homepage-discovery`.

- Owner: "the homepage feels dead — show restaurants, add menu links to the top
  pages." Now that RGP's Wraps is published (37 items) there's real content to
  surface. Added: `fetchRestaurants()` (published list) → a homepage "Menus you
  can filter right now" section (server-fetched, ISR 5m, graceful empty state),
  a new `/restaurants` browse index, a persistent **Restaurants** nav link in the
  header (every page, signed in or out) + a footer link. Cards link to each
  `/restaurants/[slug]` filtered menu.
- Web vitest 210 (+2), typecheck/lint green; `next build` regenerates the typed
  route for /restaurants. Verify-flow redesign PR-3 (verify UI) still queued.

2026-07-21 — Verify-flow redesign PR-2: Accept All + Undo. Branch `feat/verify-accept-all-undo`.

- `POST /ingestion_runs/:id/items/accept_all` — bulk-accepts every pending item,
  same defer-or-promote rule as a single accept (promote now if enriched, else
  record for the :staged batch-promote). Undo = `PATCH decision: pending` — reverts
  a decision to pending and, if the item was promoted, destroys its live Item +
  ingredient/tag joins (FK is RESTRICT, so item_id is released first). Shared
  `apply_acceptance!`; items now serialized with `position` + ordered by it.
- Next: PR-3 (verify page redesign — grouping, matching status, Accept All / Undo
  buttons). PR-1 (pipeline) deployed; re-verifying end-to-end via Chrome.

2026-07-21 — Verify-flow redesign PR-1: instant dishes + background enrichment
(backend pipeline). Branch `feat/verify-flow-redesign`. See
`docs/plans/verify-flow-redesign.md`.

- The safety invariant: `promote!` (creates the real filterable Item + ingredient/
  tag joins) must never run before a dish is enriched. The pipeline now:
  extract → **materialize dishes now** (empty payloads, `position`) → resolve
  ENRICHES the items in place (ingredients then tags) → at `:staged`, batch-promote
  any items accepted during resolving, then the publish check.
- ExtractMenuJob materializes items (moved off ResolveTagsJob); ResolveStageJob
  writes resolution onto items by position (dropped the staging-mutation);
  ResolveTagsJob enriches tags + promotes deferred accepts + stages + publishes.
  Controller: accept while `:resolving` records the decision but DEFERS promote
  (no Item without payloads). Migration: `position` on ingestion_items.
- Specs rewritten (extract/resolve×2/controller) — couldn't run rspec locally
  (no gem bundle), so ci-api is the first real run; expect to iterate. PR-2
  (Accept All + Undo) and PR-3 (verify page: grouping, matching status) next.

2026-07-21 — Failed runs no longer burn the per-user scan quota. Branch `fix/quota-excludes-failed`.

- Verifying the earlier fixes was blocked: all 5 of the reporter's daily quota
  slots were consumed by *failed* test runs (media_type/fence/bare-array errors,
  each now fixed + deployed). `runs_in_last_24h` counted every run regardless of
  status, so a user whose scans errored couldn't retry. Now excludes
  `status: "failed"` — spend is still guarded by the daily cost ceiling
  (`todays_spend_cents` sums all runs, failures included). This auto-frees the
  reporter's 5 dead slots. Spec: a failed run doesn't count toward the quota.

2026-07-21 — Tolerate bare-array resolve responses. Branch `fix/resolve-array-response`.

- Live scan failed: `resolve_ingredients_validation_failed: property '#/' of type
  array did not match ... object`. The resolve model returned a bare `[...]`
  instead of the schema's `{"items":[...]}` wrapper (any model does this
  occasionally; faster models more so). `ResponseParser#coerce_root` now wraps a
  bare array under the schema's single array-typed property before validation —
  conservative (only the unambiguous single-array-object case; genuinely-wrong
  shapes still fail). Covered against the real `ResolutionSchema` + a fenced
  variant.

2026-07-21 — Faster resolve stage (scan speed, Phase 1 of 2). Branch `feat/parallel-resolve`.

- User: "Matching ingredients…" is slow + no feedback. Traced it: ingestion is
  **3 sequential LLM calls** (extract → resolve ingredients → resolve tags) and
  the verify page shows nothing until all 3 finish. The two resolve calls are the
  wait. Agreed plan = "Both": **Phase 1** (this) faster resolve; **Phase 2** show
  dishes right after extraction + enrich (ingredients/tags) in the background,
  gating publish on enrichment.
- **Phase 1**: the resolve stages do catalog **slug-mapping**, not deep reasoning,
  so they now run on a fast Haiku model (`INGESTION_RESOLVE_MODEL`, default
  `claude-haiku-4-5-20251001`) instead of the Sonnet vision model. Extraction
  stays on Sonnet. Threaded `model:` through `timed_anthropic_call` (one place —
  request + cost pricing); added Haiku to `UsageCost` ($1/$5 per MTok). Kept the
  sequential chain — **parallelizing the two resolve jobs was deliberately NOT
  done**: `record_api_usage!`/staging are read-modify-write ("jobs run
  sequentially per run" invariant), so concurrency would need row-lock hardening
  that Phase 2's background-per-item enrichment restructures anyway.
- Specs: resolve job asserts the Haiku model; UsageCost prices Haiku. `ruby -c`
  clean; full rspec on ci-api. **Next: Phase 2 (instant dishes + bg enrich).**

2026-07-21 — Route ingestion inputs by content-type + copy/paste import.
Branch `feat/ingest-content-types` (the "next PR" from the fence entry below).

- Fixes the URL-import 400 (`media_type should be image/...`): `ExtractMenuPrompt`
  sent every input as a vision `image` block, but URL fetches come back as
  `text/html` and PDFs as `application/pdf` — neither is a valid image. Now
  routed per content-type: PDF → document block (Claude reads PDFs natively),
  text/* (URL HTML + pasted) → text block, images (jpeg/png/gif/webp) → image
  block. HEIC/HEIF still route as images (deferred; a text block of raw HEIC
  bytes would be worse — conversion is the real follow-up).
- Delivers the requested **copy/paste import**: `POST /api/v1/ingestion_runs`
  now accepts `source_text` → a `text` run storing the paste as a text/plain
  input blob through the same pipeline; capped at 50k chars
  (`INGESTION_MAX_SOURCE_TEXT_CHARS`). New `/ingest` textarea + `ingestFromText`.
- Added `AnthropicClient#document_block`, `input_kind: "text"`. Specs: prompt
  routing (image/pdf/text) + request (text run, text_too_large) + web (lib +
  paste page). Web vitest 208, typecheck/lint green; Ruby specs on ci-api.

2026-07-21 — Ingestion pipeline bugs surfaced once R2 upload worked. Branches
`fix/anthropic-json-fence` + follow-ups.

- After the R2 fix, real scans exposed downstream failures (from prod runs):
  1. **Photo (jpeg)**: extraction succeeds, then resolve fails —
     `resolve_ingredients_validation_failed: JSON parse failed: unexpected
     character: '` + "```json" + `'`. The model wraps its strict-JSON reply in a
     markdown fence and `ResponseParser` fed it straight to `JSON.parse`.
  2. **URL import**: `UrlFetcher` fetches the menu web page (`text/html`) but
     `ExtractMenuPrompt` sends every input as an `image_block` → Anthropic 400
     `media_type should be image/jpeg|png|gif|webp`. Same for direct PDF uploads.
- **This PR** fixes #1: `ResponseParser#strip_code_fence` strips a surrounding
  ```` ```json … ``` ```` fence before parsing (falls through unchanged when
  there's no fence; malformed JSON still raises). Unblocks the photo flow
  end-to-end. Spec: `spec/services/anthropic_client/response_parser_spec.rb`.
- **Next PR** fixes #2 + delivers the requested copy/paste import: route the
  extraction content block by content-type — image → image_block, application/pdf
  → document block, text/* (html + pasted) → text block — plus a `source_text`
  param + `/ingest` textarea. (HEIC/HEIF still route as images for now; iOS web
  uploads arrived as jpeg, so deferred.)

2026-07-21 — Fix menu-scan 500 (Cloudflare R2 checksum incompatibility). Branch `fix/r2-checksum-ingestion-500`.

- **User report**: signed in but "can't scan menus" — `POST /api/v1/ingestion_runs`
  returned `Ingestion request failed: 500` on both URL and photo. Prod logs
  (via `kamal app logs`) showed the blob uploads to R2 ("Uploaded file to key")
  then `Aws::S3::Errors::InvalidRequest (You can only specify one non-default
  checksum at a time.)` at `ingestion_runs_controller.rb:159`.
- **Root cause**: `aws-sdk-core 3.254` / `aws-sdk-s3 1.228` default to adding a
  CRC32 request checksum (`request_checksum_calculation: when_supported`, the
  default since 3.201). Cloudflare R2 rejects requests carrying more than one
  checksum, so every Active Storage blob op 500s (menu ingestion + dish photos).
- **Fix**: pin `request_checksum_calculation` + `response_checksum_validation`
  to `when_required` on the `r2` service in `config/storage.yml` (Active Storage
  forwards leftover keys to `Aws::S3::Client`). Added `spec/config/storage_spec.rb`
  guarding it. Needs an API deploy (deploy-api.yml auto-deploys on master merge).
- **Fallout**: each failed attempt still persisted an IngestionRun (stuck in
  `extracting`, 0 items) that counts against the 5/user/day quota — the reporter
  burned all 5 slots and now hits `quota_exceeded`. Cleaning up those dead runs
  post-deploy to unblock. **Follow-up**: a create that 500s shouldn't leave a
  committed run / shouldn't burn quota (transaction/rollback gap).
- **Also reported (queued)**: no nav path to `/ingest` for signed-in users; add
  a copy/paste (raw menu text) import option alongside URL/photo.

2026-07-21 — Fix broken Vercel web deploys (Tailwind v4 regression). Branch `fix/tailwind-v3-repin-vercel-build`.

- **Every Vercel web deploy had been failing** since Dependabot #421 (527025b)
  bumped `tailwindcss` 3.4.19 → 4.3.3. v4 moved its PostCSS plugin to
  `@tailwindcss/postcss` + CSS-first config, but `apps/web/postcss.config.mjs`
  still uses the v3-style `tailwindcss: {}` plugin, so a fresh install throws
  `pluginFactory` on `globals.css` under Next 16's Turbopack build. Confirmed on
  both #411 (fa847f5) and #422 (9329efe); the site was stuck on the last good
  deploy. Local builds passed only because `node_modules` held a stale v3.
- **Silent because CI doesn't build**: `ci-js` runs typecheck/lint/test, not
  `next build`, so only Vercel caught it — and Vercel isn't an auto-merge gate.
- **Fix**: re-pinned `tailwindcss` to `^3.4.19` (the team's prior v3 decision),
  regenerated `pnpm-lock.yaml`, and added a Dependabot `version-update:semver-major`
  ignore for tailwindcss so it can't re-bump. Verified `pnpm --filter web build`
  green with a fresh v3 install (34/34 static pages); web vitest 204, typecheck,
  lint green.
- **Follow-up (not in this PR)**: add `pnpm build` to `ci-js` so build breaks
  gate PRs instead of silently failing Vercel. A full Tailwind v4 migration
  (postcss + ui-tokens→tailwind.config rework) remains the deferred alternative.

2026-07-20 — Web auth entry, deferrable onboarding, auth analytics. Branch `feature/web-auth-entry-onboarding-skip`.

- **User asks**: (1) a direct login/signup button that doesn't route through
  onboarding, (2) a way to skip onboarding and finish it later, (3) more
  analytics on the sign-in/sign-up flows. All web.
- **Sign up in the header**: `_SiteHeader` signed-out state now shows Sign in +
  a primary **Sign up** button (was only a "Sign in" text link). Landing hero
  unchanged.
- **Resume nudge**: `GET /api/auth/session` now also returns `onboarded` — when
  signed in it reads Rails `GET /api/v1/profile` and reports
  `disclaimer_acknowledged_at != null` (fails safe to `true` on any lookup
  error, so a hiccup never nags a set-up user; no API change — the field was
  already in the payload). When `signedIn && !onboarded` the header shows a
  quiet "Food profile" link + a dismissible banner (localStorage
  `bw_profile_nudge_dismissed`); both hidden on /onboarding·/login·/signup and
  gone for good once onboarding completes. Onboarding step 1 gained a labelled
  **"Skip for now"** (same clear-draft + home as the existing Exit).
- **Auth analytics**: 3 new events in `packages/analytics` (`auth_started`,
  `auth_completed`, `auth_failed`) — auxiliary to the core funnel, PII-free
  (coarse `method`/`reason`/`status`, never email/password). login + signup
  pages fire started→completed/failed; each client gate (weak_password,
  age_unconfirmed, terms_unaccepted) and API error (wrong_credentials 401,
  rejected 422, server, network) reports its own reason. Mobile can adopt
  the same events later (deliberately deferred). No `identify()` — keeps the
  anonymous-id posture. `docs/analytics.md` + CLAUDE.md updated.
- **xhigh review addressed** (8 findings): signedIn stays a fast local read
  (onboarding status split into `/api/auth/onboarded`, so the header nav never
  blocks on Rails); nudge-dismissed flag cleared on logout + onboarded latch
  reset per user (no leak across accounts on a shared browser); signup submit
  no longer disabled on the age/terms boxes so those gate events actually fire;
  onboarded fetch latches once true (no per-nav round-trip); one-shot
  sessionStorage hint kills the post-onboarding nudge flash; shared
  `authFailureReason` helper; 422 relabelled `rejected`.
- Web vitest 201 (+13), analytics vitest 12 (+1 taxonomy assertion); typecheck
  + lint green across the workspace. No apps/api changes → ci-api untouched.

2026-07-16 — Web auth UX + session lifetime. Branch `fix/web-auth-nav-and-onboarding-exit`.

- **User report**: onboarding had no exit/skip, and "logging in does not work"
  on the live site (redirects but authed calls 401; no indication of login or
  profile anywhere). Read-only prod probes confirmed the login→Rails path is
  wired correctly and the `bw_session` cookie is valid on the `bite-worthy.com`
  apex — so login itself works. Two real defects produced the symptoms:
  - **No auth UI**: root `layout.tsx` had no header/nav — no way to reach
    `/login`, and a signed-in user saw no logged-in state. Added a client
    `SiteHeader` (Sign in ↔ Account + Log out) backed by a new
    `GET /api/auth/session` `{ signedIn }` read, so the SSR/SEO pages stay
    static instead of the root layout reading cookies.
  - **30-min session death**: `devise_jwt.rb` issued 30-minute JWTs while the
    cookie lived 30 days with no web-side refresh, so any authed call ~30 min
    post-login 401'd. Bumped `jwt.expiration_time` to 30 days to match the
    cookie (logout still revokes via jti). User chose the match-cookie option
    over wiring refresh.
  - **Onboarding exit**: persistent "Exit" on every step of the main flow
    (clears the draft, routes home); standalone "Improve my picks" keeps its
    own Cancel.
- Web: 188 vitest pass, typecheck + lint clean. API: new login-spec assertion
  (token TTL > 1 day) passes; rubocop adds no new offenses. Note: the
  `signup_spec` account-deletion example fails **locally only** (leftover seed
  data in an undroppable local test DB → review slug collision); `ci-api` is
  green for it on master, so a clean seedless CI run passes.

2026-07-16 — Deploy-api host-key pinning. Branch `fix/deploy-api-pin-host-keys`.

- **The 6de948a deploy failed** with `Net::SSH::HostKeyMismatch … fingerprint
  SHA256:GlR1Zi0t… does not match`. The box has not been rekeyed: all three of
  its current fingerprints (rsa/ecdsa/ed25519) equal the entry in the
  maintainer's local `~/.ssh/known_hosts`, and the "mismatched" key is the
  box's *real* ed25519 key. Scope that evidence honestly — there is **no
  checked-in provisioning fingerprint record**; the laptop entry is itself
  TOFU-established, so this shows only "unchanged since first connect", and a
  host-key comparison is **not** a compromise assessment either way. The
  a701eea run had SSH'd fine 7 min earlier on identical logic (6de948a changed
  only comments), so the failure was nondeterministic.
- **Root cause — a race in `ssh-keyscan -H`, reproduced both ways locally.**
  Nothing was wrong with the box's keys and nothing was intercepted:
  - `ssh-keyscan -H` writes rsa/ecdsa/ed25519 in network **arrival order**.
  - Kamal → SSHKit, and SSHKit **replaces net-ssh's known_hosts matcher** with
    its own (`backends/netssh.rb`). Its `KnownHostsKeys#keys_for` **returns on
    the first matching hashed entry**, so a hashed file yields exactly **one**
    key type — whichever won the race.
  - rsa first → SSHKit yields only the rsa key → net-ssh negotiates ed25519 →
    compares it against the lone rsa entry → `HostKeyMismatch` naming the box's
    *real* ed25519 fingerprint. **ed25519 first → verifies, deploy proceeds.**
    Same code, two outcomes, 7 min apart — exactly a701eea (pass) vs 6de948a
    (fail).
  - Plaintext entries yield *all* types for the host (`keys[h]`), so they can't
    lose this race. That is why pinning fixes it.
- **Two earlier hypotheses were wrong; recorded so the next reader doesn't
  re-run them.** (a) "Empty/partial scan" — refuted: empty known_hosts is
  silently *accepted* (net-ssh accepts a host it has no entry for), and a
  truncated line raises `ArgumentError`, so neither yields this error.
  (b) "The scan returned a wrong key, so interception can't be ruled out" —
  **withdrawn**: it came from probing `Net::SSH.start` directly, which uses
  net-ssh's own matcher and returns *all* matching keys. Kamal never takes that
  path. Probing SSHKit's matcher — the real consumer — reproduced the failure
  from correct keys alone. No security event.
- **Fix:** pinned **plaintext** host keys via a new `SSH_KNOWN_HOSTS` repo
  secret (3 lines, all types); dropped the scan; `set -euo pipefail` +
  preflight. The guard calls **SSHKit's own `KnownHosts#search_for`** rather
  than imitating it with grep/`ssh-keygen -F`, so the check cannot disagree
  with the deploy: both regex and `ssh-keygen -F` *passed* wildcard and
  `@cert-authority` pins that SSHKit yields **zero** keys for — a green check
  over an unverified deploy — and the regex also *blocked* valid rsa/ecdsa
  pins. It also rejects hashed pins outright, since those reintroduce the
  first-hash-only race that caused this incident. Verified against the live
  box: the pin resolves to 3 keys and passes; wildcard/`@cert-authority`/empty
  are blocked. Re-pin *only* from out-of-band-verified material, unhashed —
  never from a bare `ssh-keyscan`. See the note in `deploy-api.yml`.
- **Known gap — the guard looks the host up exactly as Kamal does *today*.**
  net-ssh derives its lookup key from the connection, so changing
  `apps/api/config/deploy.yml` can silently move it out from under the pin:
  `ssh: port:` → `[ip]:port`; an `ssh: proxy:` or a DNS hostname in
  `servers.web.hosts` → `host,peer_ip` (SSHKit intersects the per-name key
  sets, so a single-host-field pin yields **zero** keys). Zero keys means
  Kamal accepts the host unverified while the guard still prints OK. If any of
  those change, re-pin in the matching form. The guard fails closed on
  everything it can see; it cannot see deploy.yml.
- **Method note:** probe the client the code actually uses. Driving
  `Net::SSH.start` directly produced confidently wrong conclusions twice,
  because SSHKit swaps out the matcher underneath Kamal.
- Gitignored `biteworthy-deploy{,.pub}` (the CI deploy keypair, root on the
  API box) — it was sitting untracked and uncovered in the repo root. History
  checked: never committed. **MANUAL, user: move that keypair out of the repo
  (e.g. `~/.ssh/`); the gitignore is only a backstop.**

2026-07-15 — Web camera capture + PWA hygiene. Branch `feat/web-camera-pwa`.

- `/ingest`: added a rear-camera capture control (`<input capture="environment">`)
  beside the existing PDF/photo picker, so mobile web can snap a menu before/without
  the native app. Shared `onPickFile`; selected-file name is echoed as feedback since
  the camera input is visually hidden. Reuses `ingestFromFile` — no new API. Live
  camera / getUserMedia / offline stays the native app's job.
- PWA hygiene, no service worker: `app/manifest.ts` (→ `/manifest.webmanifest`,
  `display: standalone`, theme/bg from `@biteworthy/ui-tokens`), `viewport.themeColor`
  + `appleWebApp` metadata in `layout.tsx`, and `public/icons/icon-{192,512}.png`
  generated from the #407 512² `app/icon.png`. Favicon + apple-touch-icon come from
  the `app/icon.png` + `app/apple-icon.png` convention (#407). Verified on a dev boot:
  manifest 200 `application/manifest+json`, head tags inject, icons serve, `/ingest`
  shows the camera input.

2026-07-15 — API auto-deploy. Branch `chore/api-auto-deploy`.

- Added `.github/workflows/deploy-api.yml`: runs `kamal deploy` on merge to
  master touching `apps/api/**` (or manual `workflow_dispatch`). Builds the
  amd64 image on the runner, pushes to GHCR, SSHes root@87.99.137.181 to boot;
  `concurrency: deploy-api` serializes, `cancel-in-progress: false`. Web already
  auto-deploys via Vercel; this closes the API gap (was manual `kamal deploy`).
- **Secrets model:** one blob instead of ~17 keys — `KAMAL_SECRETS_B64` =
  base64 of `apps/api/.kamal/secrets` (decoded to the file in CI, holds every
  app secret + KAMAL_REGISTRY_PASSWORD), plus `SSH_PRIVATE_KEY` (root@box key).
  **MANUAL, user: add both repo secrets before the first run**, else the
  preflight step fails loudly. First run (on the #405 merge) went green —
  pipeline validated end-to-end. (A third secret, `SSH_KNOWN_HOSTS`, was added
  2026-07-16 — see the top entry.)
- **Secret rotation helper** `apps/api/bin/kamal-secrets-push`: re-encodes
  `.kamal/secrets` → the `KAMAL_SECRETS_B64` repo secret via `gh secret set`
  (add `--deploy` to also dispatch deploy-api). Run it after changing any
  secret value so auto-deploy picks up the new values.

2026-07-14 (post-launch fixes 2) — CORS + email. Branch `fix/production-cors`.

- **Onboarding was broken ("Could not load presets — Failed to fetch")** — the
  page is a client component that reads public taxonomy from the Rails API
  directly (`${NEXT_PUBLIC_API_BASE}/api/v1/...`), a cross-origin browser call.
  `rack-cors` (`initializers/cors.rb`) defaults `ALLOWED_ORIGINS` to localhost
  and it was never set in prod, so the API sent no `Access-Control-Allow-Origin`
  for `https://bite-worthy.com`. Fixed: `ALLOWED_ORIGINS=https://bite-worthy.com
  https://www.bite-worthy.com` in `deploy.yml` env.clear + `kamal deploy`.
  Verified header present and all 10 presets load.
- **Mailgun snag:** `SMTP_ADDRESS` switched to `smtp.mailgun.org` in deploy.yml,
  BUT the WBW Mailgun account only has `whiteboardworks.com` + a sandbox —
  **`bite-worthy.com` is NOT a domain there**, so the zone's Mailgun DNS records
  don't map to a usable sending domain and there are no bite-worthy.com SMTP
  creds. Email still unwired pending a decision (add bite-worthy.com to Mailgun /
  send from whiteboardworks.com / different account). `kamal deploy` gotcha
  recap: run `kamal` directly (not `bundle exec kamal` — it's not in the Gemfile).

2026-07-14 (post-launch fixes) — content seeding + Durango SEO. Branch
`fix/durango-diet-slugs`.

- **CRITICAL, now fixed — production DB was empty of taxonomy.** The running
  API container (Neon `neondb`, pooler host) had `ingredients=0 tags=0
  dietary_profiles=0 restaurants=0`: `db:seed` never populated the *current*
  database — during the multi-db→single-db churn, seeds ran against a Neon
  database that was later deleted, and `db:prepare` only seeds on fresh
  creation. **Solid Cache masked it** — `/api/v1/ingredients` served stale
  cached JSON, so the endpoints looked healthy while the DB was bare (the
  filter product was actually non-functional). Fixed by running
  `kamal app exec --reuse "bin/rails db:seed"` → **36 tags, 1088 ingredients,
  10 dietary profiles** (idempotent upsert). Verified via direct psql, not the
  cached endpoint. Gotcha: `kamal app exec` runs on ALL roles (web+worker)
  concurrently → the two seed runs raced ("Slug has already been taken"); the
  web run completed fully, so the data is correct. Use a single role for
  one-off data tasks (`--role web` before `app exec`, not after).
- **Durango city created** (empty) via psql INSERT so the `/durango/[diet]`
  SEO pages resolve; they self-heal from the build-time 404 via `revalidate`
  ISR once the API returns 200. Verified vegan/vegetarian/celiac/pescatarian
  now 200.
- **Fixed `DURANGO_DIET_SLUGS` drift** (this PR): `tree-nut-free`,
  `shellfish-free`, `lactose-free`, `low-fodmap` were never seeded and 404'd.
  Replaced with real slugs (`gluten-free`, `dairy-free`, `tree-nut-allergy`,
  `peanut-allergy`); updated the test to guard against the drift.
- **Still open:** real Durango restaurant content (pages show the empty state);
  Mailgun SMTP creds (SMTP_* empty); the Vercel prod deploy needed a manual
  Force-Promote (master merge didn't auto-trigger — verify future pushes).

2026-07-14 (latest) — LAUNCH: DNS cutover complete, API live over HTTPS, web
build fixed. Continuation of the provisioning session below; same branch
`chore/launch-provisioning`.

**Done:**
- **Nameserver flip landed** (user migrated the registrar to the WBW
  Cloudflare account). `bite-worthy.com` NS = cris/janet.ns.cloudflare.com,
  zone active. Verified resolving: `api → 87.99.137.181`, apex + www → Vercel
  edge (216.150.x.x via CNAME flattening).
- **API LIVE over HTTPS:** `https://api.bite-worthy.com/up` → 200 with a valid
  Let's Encrypt cert (issued automatically once DNS resolved). Taxonomy is
  seeded — `/api/v1/ingredients` and `/api/v1/dietary_profiles` return real
  data.
- **Vercel DNS staged in Cloudflare** (both DNS-only, per Vercel's new IP
  range): apex CNAME + www CNAME → `311e341e12f61b6e.vercel-dns-016.com`
  (www is a 308→apex redirect in Vercel). Cloudflare CNAME-flattening lets the
  apex CNAME coexist with the pre-existing Mailgun MX/SPF/DKIM records.
- **Web production build fixed + pushed** (commit d73c1fb): tailwind pinned to
  v3 (v4 broke postcss/config), login+signup `<Suspense>` boundaries, and
  `durango/[diet]` `revalidate=300` + empty-state fallback. `pnpm build` green
  (typecheck + lint + 180 tests).
- **Removed dead `resources :cities` route** — no controller existed, so
  `GET /api/v1/cities` returned 500. The used `/cities/:city_slug/restaurants`
  route stays; spec green on a clean test DB.

**Discovered:** production DB has the taxonomy but NO city/restaurant/menu
content — `db/seeds.rb` seeds taxonomy only; Durango restaurants come from the
ingestion/onboarding flow, not seeds, so `/durango/[diet]` shows the
empty-state fallback until content is loaded. Also: pre-existing **Mailgun**
email records (MX/SPF/DKIM) already on the zone — could serve transactional
email instead of the pending Postmark signup.

**Still manual (user):** SMTP provider (Postmark signup OR wire existing
Mailgun SMTP creds — `SMTP_*` still empty in `.kamal/secrets`); Vercel
production deploy fires on merge to `master`; Apple/Google dev accounts +
D-U-N-S; attorney (L1); DMCA agent; icon-source.svg pick; Anthropic billing.

2026-07-14 (later) — LAUNCH PROVISIONING, interactive (no tick), branch
`chore/launch-provisioning`. Handoff state for the next session:

**Done this session:**
- Hetzner server LIVE: `biteworthy-api`, **cpx21** (not cx22 — the CX/Intel
  line doesn't exist in US DCs; cpx21 = 3 vCPU/4 GB/80 GB, ~$8.5/mo — ADR
  0007 needs this correction), ash-dc1, IP **87.99.137.181**, ubuntu-24.04,
  SSH key `skylar`, root SSH verified, Docker bootstrapped via
  `kamal server bootstrap`.
- `apps/api/.kamal/secrets` built (gitignored): DATABASE_URL rewritten to
  Neon **pooler** host + sslmode=require (user's `.env` had the unpooled
  one), fresh DEVISE_JWT_SECRET_KEY, RAILS_MASTER_KEY from newly generated
  credentials (`config/master.key` + committed `credentials.yml.enc` —
  repo previously had NO credentials at all), ANTHROPIC/ADMIN from `.env`,
  KAMAL_REGISTRY_PASSWORD = fresh GitHub classic PAT
  `biteworthy-kamal-ghcr-laptop` (90d, write:packages, owner @wbwSoftware;
  `docker login ghcr.io` verified). SMTP_*/R2_* still EMPTY placeholders.
- `config/deploy.yml`: real IP in both roles; removed invalid `hooks:` key
  (Kamal 2 auto-discovers `.kamal/hooks/`; the key errors as
  "unknown key: hooks").
- Cloudflare: bite-worthy.com zone added to the WBW account
  (14eec3b118e3baabc516aac5d7ae869c) — **PENDING nameserver flip** (see
  manual items). A record `api → 87.99.137.181` (DNS only) already in the
  new zone. R2 bucket **biteworthy-blobs** created (billing already
  enabled) + Account API token `biteworthy-api-storage` (Object R&W,
  bucket-scoped) — R2_* filled in `.kamal/secrets` and deployed.
- **Worker was NOT healthy after bug (4)** — it crash-looped on
  `solid_queue_recurring_tasks does not exist`. Root cause: the multi-db
  database.yml never worked — ENV["DATABASE_URL"]'s database name
  overrides each entry's `database:` key, so primary/cache/queue/cable
  all resolved to the same Neon db while the solid_* tables existed
  nowhere (the repo's queue/cache/cable schema files were empty
  version-0 stubs; solid_queue:install had never completed). Fixed by
  flattening to a SINGLE database: real solid_queue/solid_cache tables
  added to the primary schema via migration
  `20260714120000_create_solid_queue_and_solid_cache_tables`, installers'
  config/queue.yml + cache.yml committed, connects_to dropped, unused
  ActionCable switched to async. **Verified live: Solid Queue
  supervisor/worker/dispatcher/scheduler all running, BOTH recurring
  tasks registered (purge_orphaned_restaurant_visits preserved after the
  installer clobbered recurring.yml — restored), Rails.cache round-trip
  works.** Deleted the three empty per-db Neon databases this session
  briefly created.
- **Vercel:** project `biteworthy-web` imported (team Skylar,
  whiteboard-works/biteworthy, root apps/web, Next.js preset) with
  NEXT_PUBLIC_API_BASE / COOKIE_DOMAIN / SITE_URL / POSTHOG_KEY set for
  Production+Preview; first deployment building at handoff. Custom
  domains bite-worthy.com + www still to add after build.
- **PostHog:** the WBW Cross-Product project (id 370116) lives in the
  PostHog account the browser is logged into; project token
  `phc_tstSvpFjyUwgb8wD9rbL97SvgBgQe8oUWFGubrWTVavZ` (public client
  token) — used for NEXT_PUBLIC_POSTHOG_KEY, same value for
  EXPO_PUBLIC_POSTHOG_KEY at EAS time.
- Attorney engagement email + legal review packet + 3 icon-source.svg
  drafts delivered to the user as files (Gmail connector is read-only;
  draft couldn't be placed directly).
- **DEPLOYED AND HEALTHY.** `kamal deploy` succeeded after a four-bug
  chain, each fixed + committed on this branch: (1) `hooks:` is not a
  valid Kamal 2 config key; (2) Dockerfile chown failed on dockerignored
  `log/` (mkdir -p first); (3) the pre-deploy hook ran `kamal app exec`
  before any container existed — removed, entrypoint db:prepare +
  healthcheck gate cutover instead; (4) **the web role needs
  `cmd: ./bin/rails server`** — the Dockerfile has ENTRYPOINT but no CMD,
  so the container execd nothing and exited 0 silently (empty logs,
  failed healthcheck). Web + worker both healthy on the box;
  `deploy_timeout: 300` added for cold boots. db:prepare ran clean against
  Neon (~3s). `kamal smoke` passes DB-side ("no published restaurant" =
  correct pre-seed state) and fails ONLY on public DNS resolution —
  expected until the NS flip. External probe:
  `curl --resolve api.bite-worthy.com:80:87.99.137.181 http://api.bite-worthy.com/up`
  → 301 to https (proxy routing works; TLS cert issues itself after DNS).
- `apps/mobile/.env.example`: documented previously-missing
  `EXPO_PUBLIC_WEB_BASE` (share links break to localhost without it).

**Next steps (in order):** (1) confirm `kamal deploy` completed →
`kamal app exec "bin/rails biteworthy:production:smoke EXIT_CODE=1"`;
(2) after NS flip lands, `curl https://api.bite-worthy.com/up` (Let's
Encrypt cert issues on first request); (3) R2: create Object-R&W API
token for biteworthy-blobs, fill R2_* in `.kamal/secrets`
(R2_ENDPOINT = https://14eec3b118e3baabc516aac5d7ae869c.r2.cloudflarestorage.com),
redeploy; (4) Postmark + Vercel + PostHog wiring (accounts may not exist
yet — account creation is user-only); (5) icon SVG drafts, attorney email
draft, cassette, seed. Gotcha: `kamal env push` does NOT exist in Kamal 2
(docs are stale) — secrets ship with `kamal deploy`.

**Manual items outstanding (user):** flip bite-worthy.com nameservers to
cris/janet.ns.cloudflare.com in whichever Cloudflare account currently
serves malcolm/paloma (registrar = Cloudflare; zone wasn't visible to the
info@whiteboardworks login); Anthropic billing?; Postmark/Vercel/PostHog
signups; Apple/Google dev accounts + individual-vs-org (D-U-N-S) decision;
attorney engagement (L1); DMCA agent ($6); icon-source.svg approval.

2026-07-14 — planning (interactive, no tick). Added `docs/launch-plan.md`
(two-track launch: manual Track A critical path + loop-shippable Track B
lower-the-gate + QR program) and `docs/plans/six-month-plan.md` (the
"how do we win, not just launch" reversal — three steelman-resolved
decisions on sequencing/positioning/trust, tasks split [MANUAL]/[CODE]
across 6 months, gated on the strategy §5 canaries). No code changed yet;
recommended first build = the P0 safety guardrails (filter-engine↔SQL
parity, array-sync invariant, adversarial hidden-allergen test).

2026-06-14 — post-loop interactive work (no tick number; the cron loop
stayed paused). Two workstreams landed on master after tick #147, neither
of which had a status entry until now:
- **Local-dev + refactor wave (#315–#325).** Full Docker local-dev stack
  (API + Solid Queue worker + Postgres, `compose.yaml`, see
  `docs/local-dev.md`) — #315. Then a dedup pass with no behavior change:
  single-source `API_BASE` on web + mobile (#316, #319), BaseController
  shared pagination / `photo_url_for` / `public_host` (#317, #318),
  ResolveStageJob + ResolvePrompt + TimedAnthropicCall extracted for the
  ingestion pipeline (#321–#323), proxyAuthed/relayUpstream for web
  `/api` routes (#320). Plus `docs/vision.md` + the user-facing `/story`
  page (#324–#325).
- **Legal remediation (#327–#346).** Honest privacy/ToS copy + plan
  (Phase 1, #327), then E1–E13 engineering: in-app allergen disclaimer
  + onboarding acknowledgment (#328), personal-data export / account
  deletion endpoints (#329, #330), age gate 13+ (#331), visit-history
  retention backstop job (#332), expiring + log-redacted share tokens
  (#333), analytics opt-in + dietary-field stripping (#334),
  report-a-review + DMCA intake (#335, #337), neutral default handle
  (#336), rack-attack throttling (#340), in-app review edit/delete
  (#339), public-profile leak test (#341). Then ToS disclaimers + footer
  (#343), clickwrap Terms acceptance at signup (#344), mobile signup
  opening hosted legal pages (#345), one-way NDA template (#346).
  Follow-ups tracked in `docs/plans/legal-remediation-followups.md`
  (F1–F6 + L1–L5).
Next: L1–L5 launch gates (remove DRAFT banners, lawyer sign-off) +
the human-credential-gated launch wiring — see `docs/launch-readiness.md`.

2026-06-13 05:30 — tick #147. **Phase 8.5b shipped — taste onboarding
UI (web + mobile). Phase 8 feature-complete.** JS-only PR (no apps/api
changes → ci-api/rspec/brakeman/openapi untouched).
- New "What do you love?" step between strictness and review on both
  surfaces (now 5 steps): cuisine/flavor tag chips from
  GET /api/v1/tags?families=cuisine,flavor that cycle neutral → liked
  → disliked → neutral on tap, plus an optional favorite-ingredient
  search. Skippable — taste is soft, safety is not.
- Standalone "Improve my picks": `?step=taste` (web useSearchParams,
  mobile useLocalSearchParams) opens the step alone and saves via the
  taste-only saveTaste/toTastePayload, so refining picks can NEVER
  wipe the avoid lists. Web page wrapped in <Suspense> (Next 15
  useSearchParams prod-build requirement). Entry link added to the
  TopPicksRow header on both surfaces.
- Contract: optional taste_signal_count on profile_set (analytics
  EventPropsMap + docs/analytics.md, both updated same PR; no rename).
  fetchTags + saveTaste + SaveTastePayload added to both onboarding
  libs; SaveProfilePayload extended with the 4 optional taste arrays.
- Tests: web 153 (+9: fetchTags/saveTaste lib shapes + taste-step page
  render incl. standalone-save footgun guard + improve-picks link),
  mobile 120 (+2: taste step in the of-5 flow + chip cycle); existing
  of-4 flow assertions migrated to of-5. typecheck/lint green across
  the workspace.
Next: Phase 8 done — remaining queue is human-credential-gated launch
wiring (see docs/launch-readiness.md).

2026-06-13 03:15 — tick #146. **Phase 8.5a shipped — taste onboarding
foundations** (session wrapping on user request; 8.5b = the UI half,
queued at the top of Next-up with a full handoff note).
- GET /api/v1/tags implemented — third Phase-0 route that existed
  with no controller (after restaurants index). Public,
  ?families=cuisine,flavor whitelist filter, limit cap 200. +4 specs
  (incl. injection-shaped family names ignored). rspec 465/465.
- onboarding-reducer: 4 taste arrays in DraftProfile,
  CYCLE_TASTE_TAG / CYCLE_TASTE_INGREDIENT (neutral → liked →
  disliked → neutral, one tap target covers both polarities),
  toProfilePayload now carries the four arrays (empty when step
  skipped), NEW toTastePayload for the standalone "Improve my picks"
  save — taste-fields-only PATCH so it can NEVER wipe the avoid
  lists (wholesale-replace footgun, caught in design). +3 specs,
  filter-engine 171/171; web/mobile suites untouched and green.
Next: Phase 8.5b taste onboarding UI (web + mobile) — see Next-up
for the precise remaining scope.

2026-06-13 02:40 — tick #145. **Phase 8.4 shipped — Top Picks UI
(mobile).** #311 (8.3) auto-merged on green. This PR:
- filter-engine: topPicksFromScores + tasteReasonLine + TasteReason/
  ScoredWireItem promoted from the web app into the shared package
  (one selector, web + mobile can't drift); MIN_POSITIVE_PICKS /
  TOP_PICKS_COUNT constants replace magic numbers in topPicks too.
- Web TopPicksRow now imports the shared helpers (deletes its local
  copies; component + tests unchanged otherwise — 144/144 still).
- Mobile: _TopPicksRow horizontal card strip (photo, name, "Because
  you like…" line, Why-these explainer with the taste≠safety copy)
  wired above the menu sections in restaurants/[id]; rawItems state
  added beside sections, same as web. Cards push /items/:id.
  taste_score/taste_reasons added to the mobile RestaurantItem type.
- Tests: +24 vitest filter-engine (163), +5 mobile jest (118):
  thresholds, anonymous null-score no-op, hidden exclusion,
  tie-breaks, reason-line shapes, card navigation, explainer.
Next: Phase 8.5 taste onboarding step (web + mobile) — closes
Phase 8.

2026-06-13 02:05 — tick #144. **Phase 8.3 shipped — Top Picks UI
(web).** #310 (8.2) auto-merged on green. This PR (web-only):
- New TopPicksRow above the menu sections: horizontal cards (photo,
  name, "Because you like Spicy & Basil" line from taste_reasons),
  "Why these?" explainer whose copy explicitly says everything below
  passed the dietary filter (taste ≠ safety rule).
- Selection uses the SERVER's Phase 8.2 scores — no client
  recompute: top 5 visible score>0, nothing under 3 positive picks.
  Anonymous/zero-signal payloads carry null scores → row absent,
  page byte-identical to pre-8.3.
- RestaurantClient keeps rawItems state alongside sections so picks
  survive strictness refetches. taste_score/taste_reasons added to
  the web RestaurantItem type.
- Deviation noted: plan card lists "price" — the items endpoint has
  no price field (prices live only on ingestion payloads), so cards
  ship without it; surfaced rather than silently extending the API.
- +11 vitest (web 144/144): thresholds, null-score anonymous, hidden
  exclusion, sort ties, reason-line shapes, explainer toggle, links.
Next: Phase 8.4 Top Picks UI (mobile).

2026-06-13 01:30 — tick #143. **Phase 8.2 shipped — taste scoring
engine, SQL + TS in one PR.** #309 (8.1) auto-merged on green.
- New TasteScoring service: one sanitized SQL query per request
  (unnest/array_agg intersections, MAX(popularity) window,
  AVG(visible reviews) join); weights live in WEIGHTS and reach the
  SQL through placeholders so the constant and the expression can't
  drift. Brakeman-clean (first draft interpolated quoted values —
  flagged it; rewrote with sanitize_sql_array).
- Items endpoint: taste_score + taste_reasons ("because you like…"
  ids + names) per item; sort flips to score DESC, popularity DESC,
  name ASC only when the signed-in caller's profile has signals
  (presets/tokens/anonymous = untouched legacy payload, score null).
  Taste never hides: negative-score items stay visible. Avoid-listed
  ids subtracted from signals before scoring (filter wins).
- filter-engine: scoreItem/topPicks/hasTasteSignals + TASTE_WEIGHTS.
  topPicks: top-5 visible score>0, none under 3 picks; hidden items
  still normalize popularity (matches the SQL window).
- Parity contract: shared fixture (4 items × 2 profiles incl.
  avoid-overlap) asserted to 4dp by BOTH vitest and rspec.
- +21 vitest (139 total), +16 rspec (461 total: 10 parity/scoping +
  6 endpoint). rswag items schema + openapi-export + codegen in-PR.
Next: Phase 8.3 Top Picks UI (web).

2026-06-13 00:35 — tick #142. **Phase 8.1 shipped — taste signal
schema + profile API.** #308 (7.3) auto-merged on green. This PR:
- Migration: liked/disliked_ingredient_ids + liked/disliked_tag_ids
  uuid[] (default {}) on user_profiles; no GIN (read-side only).
- UserProfile validations: liked∩disliked = 422 ("loved AND hated"
  silently cancels in scoring — fail loud), unknown UUIDs = 422.
  Avoid-overlap is deliberately ALLOWED (filter wins; scoring
  ignores it in 8.2). NOTE: the plan said "same validation pattern
  as the avoid arrays" but the avoid arrays have NO existence
  validation — taste arrays are stricter than avoid; flagged in the
  PR rather than silently matching the looser precedent.
- GET/PATCH /api/v1/profile round-trips the four arrays (wholesale
  replacement, same as avoid). rswag schema + body params updated,
  openapi-export + api-types codegen in-PR.
- +5 request specs (defaults, round-trip, both-lists 422, unknown
  UUID 422, avoid-overlap OK). rspec 445/445; brakeman clean; JS
  typecheck/lint/test green.
Next: Phase 8.2 taste scoring engine (SQL + filter-engine, one PR).

2026-06-12 22:55 — tick #141. **Phase 7.3 shipped — scan-to-menu flow
stitched end-to-end. PHASE 7 FEATURE-COMPLETE.** #307 (7.2)
auto-merged on green. This PR (all mobile):
- Home search-miss is now a CTA carrying the typed name →
  /ingest?name=… prefills the new-restaurant form; result rows pass
  ?from=search.
- /ingest accepts ?restaurantId&restaurantName (skips the picker) —
  used by the new "📷 Menu changed? Re-scan" entry on the restaurant
  screen (server-side Phase 6.2 ownership rules unchanged).
- Verify screen: pipeline stages render human copy ("Reading the
  menu…" / "Matching ingredients & tags…"); finishing the deck
  refetches the run and deep-links to /restaurants/:id?from=scan —
  celebratory copy when the 80% auto-publish tripped, threshold
  explainer otherwise; "nothing to verify" also links out.
- restaurant_tap now uses the carried ?from (search | scan; default
  direct) — existing event, no taxonomy change.
- Tests: +2 ingest entry-point specs, new verify.render.test.tsx
  (4 specs: stage copy, published deep-link, sub-threshold link,
  nothing-to-verify), +2 full-screen restaurant specs (re-scan
  route, from-param tracking), home specs updated. Mobile jest
  113/113 (+11); typecheck + lint green. No API changes.
Next: Phase 8.1 taste signal schema + profile API.

2026-06-12 19:05 — tick #140. **Phase 7.2 shipped — real mobile home
screen.** The Phase-0 "Pre-MVP" placeholder is gone: debounced
(300ms) restaurant search → tap into the filtered menu, scan CTA →
/ingest, profile link → /onboarding; search-miss copy nudges toward
scanning. API: implemented the GET /api/v1/restaurants index that
was routed since Phase 0 but had no action (500'd) — published
scope, ?q= ILIKE with sanitize_sql_like, 25-row cap, summary
serializer incl. lat/lng for the deferred near-me sort
(expo-location followup). +4 request specs (440 examples green),
+3 lib specs, +5 home.render specs (mobile jest 102/102); typecheck,
lint, brakeman all green. #306 (7.1) auto-merged on green while this
was in flight; branch rebased onto it. Next: Phase 7.3 stitch the
scan-to-menu flow end-to-end.

2026-06-12 12:10 — tick #139. **Phase 7.1 shipped — real camera
capture.** Also logging tick #138 retroactively (its status entry
was deferred to dodge a same-line squash conflict with #304):
- Tick #138 / PR #305: **Phase 6.6 mobile community scan flow** —
  RestaurantPicker ahead of capture (create + did-you-mean rows +
  force), manual UUID fallback, upload routes into swipe-verify,
  friendlyScanError copy. mobile jest 94/94 (+12). **PHASE 6
  COMPLETE — anyone-can-scan works end to end on web + mobile.**
- Tick #139 / this PR: **Phase 7.1** — the Phase 2.6 mock-URI
  capture is now real: CameraView ref + takePictureAsync
  (quality 0.7 keeps pages under the 10 MB cap), capturing busy
  state, permission rationale copy, and hard-denial
  (canAskAgain: false) deep-links to system settings via
  Linking.openSettings. Camera mock upgraded to a forwardRef
  exposing takePictureAsync. mobile jest 97/97 (+3); typecheck +
  lint green. Caveat (honest): verified in jest with the camera
  module mocked — real-device capture still needs a human phone
  test, noted in the PR.
- #304 (6.5) merged after a re-run: its CI failure was the KNOWN
  onboarding flake ("renders a chip per preset", 5s timeout, third
  occurrence incl. pre-fix) — recurrence noted in Discovered.
Next: Phase 7.2 real mobile home screen.

2026-06-12 11:40 — tick #137. **Phase 6.5 shipped — web community
scan entrypoint.** #303 (6.4.1) merged. This PR (web):
- 4 new Next proxies: POST /api/restaurants, GET run, GET run items,
  PATCH item decision (cookie-JWT pattern from Phase 4.1).
- lib/ingestion.ts: createRestaurant (409 → typed duplicates
  result), fetchRun/fetchRunItems/decideRunItem,
  friendlyIngestionError (429 quota / 503 budget / 403 foreign-draft
  → human copy).
- /ingest reworked into the 2-step community flow:
  NewRestaurantPicker (create + "did you mean?" cards + force) →
  URL/PDF upload → push to NEW /ingest/verify/[runId] page: polls
  pipeline status (3s), then VerifyItemRow accept/reject list with
  the 80%-threshold progress line + published banner linking to the
  restaurant page.
- Tests: +9 lib (dedupe/force/error mapping), +8 RTL (picker cards,
  force resubmit, verify row wiring/badge/error).
War story: vitest 4 flags rejected mock results as unhandled iff
the mock was cleared in a beforeEach — empirically isolated;
per-test impls + last-called assertions instead (commented in both
test files). Also the known Next typedRoutes dynamic-push cast
(#274 precedent). web vitest 133/133; typecheck 10/10; lint 6/6.
Roadmap: 6.1–6.5 ticked into Done. Cities note: no cities index
endpoint exists (Phase-0 stub route), so the picker takes a city
slug defaulting to durango — fine for the launch market. Next:
Phase 6.6 mobile entrypoint.

2026-06-12 11:10 — tick #136. **Phase 6.4.1 — three codex P2s from
#302 fixed forward.** (1) community_published scope now also catches
seeded restaurants that received a community RE-scan (EXISTS on
suggested items, not just created_by). (2) confirm-all no longer
graduates an item whose ai-suggested joins remain — item.confidence
only flips when EVERY association is confirmed (strict mode keys
off item.confidence). (3) New Avo CommunityRuns filter on the
ingestion-runs resource (runs by non-admin users). rspec 436/436
(+1 net). Next: Phase 6.5 web community scan entrypoint.

2026-06-12 10:55 — tick #135. **Phase 6.4 shipped — moderation
visibility.** #301 (6.3) merged, zero codex findings. Loop cadence
shortened to 15 min by owner. This PR:
- `Restaurant.community_published` scope + Avo boolean filter on the
  restaurants resource (+ created_by_user fields).
- `Restaurant#confirm_community_associations!` + Avo bulk action
  "Confirm community menu → strict-mode visible": flips
  suggested/human joins + item confidence to confirmed via
  update_all (id arrays untouched — only ids sync via callbacks).
  Deliberately skips source:ai rows — admin endorses the human
  verifier, not the model. Returns counts for the admin message.
- /admin/dashboard: "Community ingestion (today, UTC)" card —
  community run count (non-admin users) + spend vs ceiling using
  EXACTLY the same UTC-day window the 6.1 ceiling enforces; warns
  at ≥80%.
War story: endless-range-at-end-of-line Ruby parse trap — `x = t..`
consumed the next line as the range end → PG DatetimeFieldOverflow.
Parenthesized + commented. rspec 435/435 (+7); brakeman 0.
Next: Phase 6.5 web community scan entrypoint.

2026-06-12 10:20 — tick #134. **Phase 6.3 shipped — community
self-verify + suggested-confidence trust model.** #300 (6.2) merged
with zero codex findings. This PR:
- IngestionItems endpoints widened from admin-only to
  creator-or-admin (`ensure_run_access!`); ownerless runs stay
  admin-only; strangers 403.
- `IngestionItem#promote!(decided_by:)` — admin or legacy no-arg
  call sites (Avo is admin-gated) promote `confirmed`; a community
  scanner verifying their own run promotes `suggested` on the Item
  AND every ItemIngredient/ItemTag join (source stays `human`).
- End-to-end spec proves the safety contract: a community-promoted
  item is hidden under `?strictness=strict` with reason
  `unconfirmed_strict` and visible under balanced — strict-mode
  users never see unconfirmed community data.
rspec 428/428 (+5); brakeman 0. maybe_publish! unchanged (80%
threshold now reachable by community runs — that's the feature).
Next: Phase 6.4 moderation visibility (Avo scope + confirm-all +
dashboard counters).

2026-06-12 03:45 — tick #133 (part 2). **Phase 6.2 shipped —
community restaurant creation + dedup.** #299 (6.1.2) merged.
- New migration: `restaurants.created_by_user_id` (nullable FK).
- `POST /api/v1/restaurants` (authenticated): name + city_slug +
  optional street/postal → draft restaurant recording creator;
  unique slug via parameterize + numeric suffix.
- Dedup guard: pg_trgm `similarity(name, ?) > 0.45` within the same
  city → 409 `possible_duplicate` + up to 5 candidates (id/slug/
  name/status/street); `force: true` overrides. Threshold calibrated
  against live pg_trgm scores: true variants 0.50–0.65, different
  restaurants ≤0.42 ("Durango Diner"/"Durango Bagel").
- Ingestion ownership rule: non-admins may only scan drafts they
  created or published restaurants; foreign drafts 403.
rspec 423/423 (+13); brakeman 0. Deviation from subplan, surfaced
honestly: no rswag spec for the new endpoint — NONE of the
restaurant/ingestion endpoints were ever rswag'd, so openapi/codegen
doesn't change; added a Discovered entry to rswag the lot in one PR.
Next: Phase 6.3 self-verify + community-trust promotion.

2026-06-12 03:05 — tick #133 (part 1). **Phase 6.1.2 — two codex P2s
from #298 fixed forward.** (1) Over-quota callers could still force
an outbound URL fetch: a cheap unlocked limits pre-check now runs
before UrlFetcher; the authoritative check still re-runs under the
advisory lock. (2) Billed 200s that failed schema validation never
accrued usage: all three jobs now record_api_usage! in the
ValidationError rescue before fail!. rspec 410/410 (+2). Part 2 of
this tick: Phase 6.2.

2026-06-12 02:35 — tick #132. **Phase 6.1.1 — community ingestion
hardened per codex review of #297.** All three codex findings were
real and are fixed forward:
- **P1 (cost ceiling read a column nothing wrote):** confirmed —
  no job ever wrote `api_cost_cents`. AnthropicClient now exposes
  `last_usage`; new `Ingestion::UsageCost` prices it (sonnet-4-6
  rate card, cache-read 0.1x / cache-write 1.25x, ceil per call so
  sub-cent calls can't leak the ceiling); all three pipeline jobs
  call the new `IngestionRun#record_api_usage!` (cost + cached/
  uncached token columns + model stamp). The Phase 2.9 dashboard
  starts showing real numbers too.
- **P2 (quota TOCTOU race):** quota check + INSERT now serialized
  per user via `pg_advisory_xact_lock(hashtext(user_id))`; admins
  skip the lock. URL fetch happens BEFORE the lock so a slow
  upstream can't hold a DB transaction open.
- **P2 (unbounded multipart uploads):** per-run caps — max files
  (`INGESTION_MAX_INPUT_FILES`, 10), per-file bytes
  (`INGESTION_MAX_INPUT_FILE_BYTES`, 10 MB = UrlFetcher's cap),
  content-type allowlist (jpeg/png/heic/heif/webp/pdf). Applies to
  admins too.
rspec 408/408 (+14); brakeman 0. Next: Phase 6.2 community
restaurant creation + pg_trgm dedup.

2026-06-12 02:00 — tick #131. **Phase 6.1 shipped — anyone can create
ingestion runs.** Plan PR #296 merged. This PR drops `ensure_admin!`
from POST /api/v1/ingestion_runs and adds the community guardrails:
per-user rolling-24h quota (`INGESTION_RUNS_PER_USER_PER_DAY`,
default 5 → 429 `quota_exceeded`) + global daily spend ceiling over
`api_cost_cents` (`INGESTION_DAILY_COST_CEILING_CENTS`, default
$20 → 503 `cost_ceiling_reached`); admins bypass both. Both vars
documented in `apps/api/.env.example`. The non-admin-403 spec became
a non-admin-201 spec; 7 new limit specs (quota boundary, rolling
window, per-user isolation, prior-day spend ignored, admin bypasses).
rspec 394/394; brakeman 0 warnings. Note: ingestion_runs has no
rswag spec (pre-existing gap — openapi.json never covered it), so no
codegen delta. Next: Phase 6.2 community restaurant creation +
pg_trgm dedup.

2026-06-12 00:05 — tick #130 (interactive session, loop restarted).
**Owner approved the product-vision arc; Phases 6–8 planned and
queued.** Owner restated the BIG goal (anyone scans any menu → full
import incl. ingredients/prices/photos → personalized "most likely
to enjoy" view) and greenlit an overnight 30-min loop to ship it.
Gap analysis: pipeline/extraction/filtering largely built; gaps are
(A) ingestion is admin-only, (B) no taste ranking — only avoid-list
hiding, (C) mobile camera ref TODO + placeholder home screen, (D)
nothing deployed (human-gated). This PR commits the plan:
`docs/plans/phase-6.md` (anyone-can-scan: quotas, cost ceiling,
community restaurant create + pg_trgm dedup, self-verify with
suggested-confidence trust model, moderation visibility, web+mobile
entrypoints), `docs/plans/phase-7.md` (camera wiring, real home
screen, end-to-end scan flow), `docs/plans/phase-8.md` (taste
signals schema, SQL+TS scoring parity, Top Picks UI, taste
onboarding) + roadmap Next-up queue (14 unblocked items, launch
wiring stays [BLOCKED] at bottom). Next: Phase 6.1.

2026-06-11 23:29 — tick #129 (interactive session). **Automation
hardening shipped; branch protection enforced.** Owner asked for the
longterm-development automations; plan written to
`docs/automations-todo.md` (#277), then items 1-6 shipped via five
parallel subagent PRs, all merged:
- #280 ci-js/ci-api report on every PR (path filters moved inside via
  a `changes` job); Brakeman now blocking; codegen drift check prints
  fix commands on failure.
- #278 nightly full-suite run against master + failure issue
  (`ci-nightly` label, mentions @shadoath).
- #281 migration guard (fails PRs editing shipped migrations).
- #279 dependabot ignores for Expo-managed packages (+ expo group
  removed).
- #283 monthly `expo-align.yml` (expo install --fix → verify → PR).
Then: **required status checks applied to master branch protection
via API** (typecheck · lint · test / rspec · brakeman · rubocop /
javascript-typescript / ruby; strict off, admins not enforced) —
verified blocking red dependabot PRs immediately.
War story in between: expo-group bump #276 auto-merged minutes before
#279's ignores landed and re-broke mobile (react-native 0.86 drops
the jest preset jest-expo needs). First dispatched expo-align run
caught the react-test-renderer mismatch in its test gate exactly as
designed but couldn't fix it; #292 realigned the deps to SDK 56 and
taught the workflow to sync react-test-renderer after --fix.
Discovered en route: auto-merged PRs never trigger master-push CI
(merge attributed to GITHUB_TOKEN, events suppressed) — the nightly
run is the only thing exercising master directly.
Remaining TODO items are launch-blocked (P2) or human-decision (P3);
see docs/automations-todo.md.

2026-06-11 23:05 — tick #128 (interactive session). **Master CI was
red; restored green.** Tick #127's docs PR (#273) failed both CI
workflows — the failures predated it. The June dependabot wave
(#227-#272, ~45 PRs) auto-merged with required checks apparently not
enforced on the new org, accumulating four JS breaks and two API
breaks. Fixes shipped as two PRs:
- #274 (ci-js): posthog-react-native 4.45 JsonType cast in the mobile
  adapter; reanimated pinned back to Expo 56's bundled 4.3.1 + missing
  react-native-worklets@0.8.3 peer added; jest-expo → ~56.0.4 with
  jest/@types/jest pinned to 29 (jest-expo is built on jest-29
  internals; jest 30's runtime crashed its environment);
  react-test-renderer 19.2.6 added to match react exactly; `as Route`
  casts for Next typedRoutes on login/signup. Verified: typecheck
  10/10, lint 6/6, test 8/8 (mobile 82/82), codegen:check clean.
- #275 (ci-api): image_processing 2.0 dropped mini_magick from the
  dependency tree but Ingestion::DishPhotoCropper requires it —
  declared explicitly (~> 5.3). Also fixed 3 ingestion_runs specs that
  were red since #223: the SSRF guard resolves DNS, WebMock doesn't —
  stubbed Resolv for the spec host. Verified: rspec 387/0.
Process flags for the human (also in roadmap Discovered): re-enable
required checks on master branch protection; stop dependabot from
bumping Expo-managed native deps past the SDK's bundled versions.

2026-06-11 22:13 — tick #127 (interactive session, not the cron loop).
**Docs sync after ~5 weeks of drift.** Since tick #126, master advanced
through #218-#225 without status/roadmap updates:
- #218 shipped Phase 5.8-wiring (posthog-js + posthog-react-native →
  9 funnel events) — the roadmap still listed it as BLOCKED Next-up #1.
  Ticked it into Done; launch-readiness step 7 now shows only the
  human key-setting steps.
- #221 thai-menu test fixtures; #222 .env.example docs; #223 SSRF +
  CSRF fixes; #224 security dep bumps; #225 compose.yaml for local
  Postgres.
This PR also refreshes CLAUDE.md + all READMEs against shipped
reality (Phase 1.6 codegen is live, packages/analytics exists, local
Postgres via compose.yaml, ci-api installs ImageMagick) and finishes
the Fly.io → Kamal/Hetzner reference sweep the owner confirmed
("Kamal Hetzner is the new standard"): apps/api README email/blob
sections, production.rb + email_smoke.rb comments, web .env.example.
Queue state: both remaining Next-up items (5.9-wiring, 5.1.1-wiring)
stay credential-gated; loop remains paused.

