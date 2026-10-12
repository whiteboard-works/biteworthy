# Filter loop — first slice: one signed-in path that works

> **Archived 2026-10-12: every box is ticked and nothing links here.** Read-only.

Living plan. Started 2026-09-08. Status: in progress.

## Principle

The idea is right. The software fails before the idea gets a chance: no menu,
no surviving filter, no usable scan. Next stretch is one signed-in path that
opens a real menu, hides the unsafe dishes, and says why. Everything else
waits.

## Keep (do not cut)

These are permanent:

- The filter loop: hide unsafe dishes and say why, every time.
- Short dietary-first onboarding.
- Strictness as a dial (relaxed / balanced / strict), not a second product.
- Honest safety copy: a filter, not a guarantee.

## Cut (from the first-run path, not delete the features)

Remove from the path a new user is pushed down:

1. Coming-soon iOS/Android badges and the "apps drop" email waitlist as the
   primary thing a signed-in user sees on `/`. The web app is the product.
   Signed-out may still mention apps coming soon, but it must not outrank
   trying the web app. `[CODE]` **This PR.**
2. First-run chrome that is not the filter loop: public profiles, MCP tokens,
   connected apps, unlinked `/history`, `/press`, `/updates`. Do not delete
   those pages. Remove them from the path a new user is pushed down.
   `/history` can stay if it stays out of the header until there is something
   to show. `[CODE]` **Later.**
3. Strategy drift toward "what should I order here?" / taste-first until the
   dietary filter actually finishes. Do not ship that positioning. Homepage,
   story, and onboarding stay dietary-first. `[COPY]` **Later.**
4. "Suggest a fix" that asks for ingredient or tag slugs. Later work:
   confirm/dispute in human language, not slugs. Do not build that UX in this
   PR. `[CODE]` **Later.**
5. Copy that claims a 30-restaurant Durango seed when the published count is
   not 30. Live site had 3 published restaurants on 2026-09-08; a fresh local
   DB seeds taxonomy only (0 restaurants). Copy must follow the real published
   count, or say we are adding menus, without a fake 30. `[COPY]` **This PR.**

## Improve now (this PR)

These are bugs:

1. **The diet preset must survive signup.** `[CODE]` **This PR.**
   
   Walked locally 2026-09-08: selected Celiac in onboarding, saved a balanced
   profile, landed signed in. Account (`/profile/settings`) showed
   celiac-related avoid ingredients but Diet preset said `Current: None`.
   
   **Hypothesis verified:** onboarding expands the preset into avoid lists
   client-side via `toProfilePayload` and never sends `dietary_profile_slug`,
   so `primary_dietary_profile_id` stays null even though the avoid IDs are
   saved. Settings "Apply a preset" and the chat tool both set it correctly
   because they pass the slug to the server.
   
   **Expected:** after choosing Celiac in onboarding, Account shows Celiac as
   the current preset, and the profile echoes that selection.

2. **A restaurant page with no filter must not claim the list matches a
   filter.** `[CODE]` **This PR.**
   
   Live public Chamayo (`/restaurants/chamayo`) said "Showing 36 items that
   match your filter" and "No filter · balanced". If there is no profile and
   no share token, say the menu is unfiltered, and the count must not say
   "match your filter".
   
   **Verified:** both web and mobile hardcode "that match your filter" in the
   summary, never checking `filter.source`. The badge is already correct —
   `filterSourceLabel` maps `source: 'none'` → `"No filter"`.
   
   **Expected:** when a filter is applied, keep the match language and the
   why-hidden behavior. When `filter.source === 'none'`, say the menu is
   unfiltered in the count line.

3. **Scan must not be a dead promise.** `[CODE]` **This PR.**
   
   `/chat` is the only add-a-menu path and requires an account. Locally,
   sending "What can I eat?" created an Untitled conversation and returned:
   "The assistant is not configured correctly on our side, so it cannot answer
   at all. Trying again will not help — this one is ours to fix."
   
   That message is fine when the assistant key is missing. What is not fine:
   empty restaurants ("No published menus yet" / "Add one from a photo") and
   the signed-in homepage CTA dump the user into a path that cannot work, with
   no honest fallback.
   
   **Verified:** there is no proactive check for `ANTHROPIC_API_KEY`. CTAs
   always promise photo scanning; a missing key only surfaces after a turn
   fails. Empty states (`RestaurantSearch`, mobile home, `HeroCta`,
   `FeatureRow`) all route to `/chat` unconditionally.
   
   **Expected:** fix the empty states and CTAs so they do not promise a scan
   the deployment cannot run. Do not invent an API key. If the assistant is
   unconfigured, the UI should say so before the user types, and the
   empty-menu recovery should not pretend a photo add will succeed.

4. **Coverage is the day-one product. Do not fake restaurants.** `[MANUAL]`
   **This PR.**
   
   If a seed/import already exists for published demo menus that does not need
   an Anthropic key or production credentials, use it so local and the plan
   can show one filtered menu. If it cannot be done without secrets or human
   review, document the exact manual step in the plan and do not stub fake
   dishes.
   
   **Status:** the Durango seed rake task (`biteworthy:seed:durango`) exists
   and requires a CSV (`durango.csv`, gitignored). An example template with 3
   rows ships in `docs/seeds/durango.csv.example`. Seeding does not require an
   API key, but publishing does require a human to review and accept staged
   items. The 80%-accept moderation gate remains.
   
   **Manual step:** to see a filtered menu locally, an operator must seed
   restaurants (`bin/rails biteworthy:seed:durango`) and then publish their
   staged items through the admin moderation UI (`/admin/ingestion-runs`).

## Later (not this PR)

Document these; do not implement:

- **Human-language suggest-a-fix** (confirm/dispute), not slugs. `[CODE]`
- **Near-me, multi-profile, taste quiz first, contribution identity / city
  rank, freemium, BiteWorthy-safe badge.** `[CODE]`
- **Native app store submit** (Apple/Play/icon). Leave coming-soon on
  signed-out marketing, quieter. `[MANUAL]`
- **Legal:** draft banners on privacy/terms, and the privacy sentence that
  claims reviews/profile are not sent to Anthropic if chat embeds them. Note
  as `[MANUAL]` / existing legal docs, do not rewrite legal copy here.
  `[MANUAL]`
- **Local ops note** (not a product feature): compose bind mounts on this
  environment do not see the workspace checkout; not this PR's problem.
  `[OPS]`

## Done for this PR

Acceptance criteria, checked only when the code actually does them:

- [x] `docs/plans/filter-loop.md` exists and lists every item above, with this
      PR's items checked only if the code actually does them.
- [x] A new user who picks Celiac in onboarding sees Celiac as the current
      preset on Account, and the avoid list still matches that preset.
- [x] Unfiltered restaurant pages do not say items match a filter.
- [x] Signed-in `/` does not lead with app waitlist / coming-soon apps.
- [x] Published-count copy does not claim 30 unless 30 are published.
- [x] Empty restaurant and scan CTAs do not promise a working photo-add when
      the assistant is not configured.
- [x] Tests cover the preset-survives and unfiltered-copy cases.
- [x] No second filter implementation. `Menus::Filter#reasons_for` stays the
      only place an item becomes visible or hidden. Do not write
      `items.ingredient_ids` or `items.tag_ids` directly. Do not edit
      `_legacy/` or already-shipped migrations. Do not rename analytics events.
