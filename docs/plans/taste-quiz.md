# Taste-Profile Quiz — onboarding flow spec

> Discovery-led onboarding (see `docs/strategy-2026-h2.md` §7). Goal: in ~6 taps,
> build a taste profile good enough to power Top Picks for a brand-new user with
> **no dietary restrictions** — restrictions become an optional setting, not the
> identity. Writes only to the existing `liked/disliked_{tag,ingredient}_ids`
> arrays; no new persistence model.

**Status:** draft · **Created:** 2026-06-19

---

## Reality check — what we have to build with

The taste engine is fully built (`taste_scoring.rb` scores server-side;
`packages/filter-engine/src/taste.ts` selects and phrases Top Picks from those
scores). The constraint is **vocabulary**, from `apps/api/db/seeds/tags.yml:92`:

| Family | Real tags today | Count |
|---|---|---|
| `cuisine` | Italian, Mexican, Thai, Japanese, Indian, American | 6 |
| `prep` | Fried, Grilled, Raw, Smoked | 4 |
| `flavor` | **Spicy, Sweet** | 2 |

**12 taste tags total.** Hero ingredients exist for love/hate cards
(`apps/api/db/seeds/ingredients.yml`): `herb-cilantro`, `herb-basil`,
`herb-garlic`, `fruit-lemon`, `fruit-olive`, mushroom, etc. — plus on-demand
`searchIngredients(q)` (≤20 results).

### Three implementation realities (do not skip)

1. **Flavor vocabulary is too thin for a "rich" quiz** (only Spicy + Sweet).
   Cuisine + hero-ingredients carry v1. **Prerequisite for a genuinely good
   quiz:** expand the `flavor` family (e.g. Savory/Umami, Sour/Tangy, Smoky,
   Creamy, Herby, Cheesy) and optionally add a `texture`/`format` family. Adding
   taxonomy nodes is admin-gated ltree work — small, but it gates quiz quality.
2. **`fetchTags` defaults to `['cuisine','flavor']`** (`apps/web/src/lib/onboarding.ts:69`)
   — the quiz must call `fetchTags(['cuisine','prep','flavor'])` to load prep.
3. **The reducer only exposes `CYCLE_TASTE_TAG` / `CYCLE_TASTE_INGREDIENT`**
   (neutral → liked → disliked → neutral; `onboarding-reducer.ts:119`). That
   3-state cycle is wrong for quiz buttons (a multi-select "pick what you like"
   that deselects to *disliked* is a bug; a love/pass card needs to land on a
   specific state). **Add explicit actions** `SET_TASTE_TAG {id, state}` and
   `SET_TASTE_INGREDIENT {id, state}` (state ∈ `liked|disliked|neutral`), keep
   the cycle for the existing chip UI, and keep `onboarding-reducer.test.ts`
   green. Small, clean addition.

---

## The flow — 6 screens, skippable after screen 3

Each screen writes concrete signals. A persistent **"Skip → see my picks"**
appears from screen 3 on; the minimum viable profile is a couple of cuisine taps.

### Screen 1 — Cuisines *(multi-select)*
**"Which cuisines make you hungry?"** — 6 chips (Italian, Mexican, Thai,
Japanese, Indian, American). Tap = love.
→ `SET_TASTE_TAG {cuisineTagId, 'liked'}`; tap again → `'neutral'`.

### Screen 2 — Heat *(single tap, 4-point)*
**"How much heat do you like?"** — None · Mild · Medium · Bring the fire.
→ None/Mild → `SET_TASTE_TAG {spicyId, 'disliked'}` · Medium → `'neutral'` ·
Fire → `'liked'`. Maps to the real `flavor:Spicy` tag.

### Screen 3 — Sweet tooth *(single tap)*
**"Do you go for something sweet?"** — Always / Sometimes / Rarely.
→ Always → `SET_TASTE_TAG {sweetId, 'liked'}` · Rarely → `'disliked'` ·
Sometimes → `'neutral'`. *(This is the last of the two real flavor tags — when
the flavor family is expanded (prereq #1), insert a "pick the flavors you love"
multi-select here instead.)*
— **"See my picks" unlocks here.** —

### Screen 4 — Cooking style *(multi-select)*
**"How do you like it cooked?"** — Grilled · Fried · Raw (sushi/ceviche) ·
Smoked. → `SET_TASTE_TAG {prepTagId, 'liked'}` per pick. *(Requires fetching the
`prep` family — reality #2.)*

### Screen 5 — Hero ingredients *(forced love/pass cards)*
A small deck of polarizing ingredients: **Cilantro, Olives, Mushroom, Garlic,
Basil, Lemon** (curated preset of seed slugs, no typing — fast). Each card:
**♥ Love** / **✕ Pass** / *skip*.
→ Love → `SET_TASTE_INGREDIENT {id, 'liked'}` · Pass → `'disliked'`.
This is the highest-signal, most-fun screen (the classic "cilantro: love or
hate"). Keep it to ~5–7 cards.

### Screen 6 — Restrictions *(optional, gentle link — NOT a step)*
**"Anything you avoid? Allergies or diets — optional."** A skippable link into
the existing dietary preset/avoid-list flow. This is the discovery-led demotion:
restrictions are a setting underneath, not a gate in front. Restricted users who
tap through get the full honest-disclosure filter; everyone else never sees it.

### Done
Build the payload with `toProfilePayload(state, presets)` (full onboarding) or
`toTastePayload(state)` (taste-only) → `PATCH /api/v1/profile` (web proxy
`/api/profile`). Server validates liked/disliked are disjoint (422 otherwise);
"filter wins" means avoided IDs are ignored by scoring, never shown.

---

## Signal → array mapping

| Screen | Dimension | Reducer action | Lands in |
|---|---|---|---|
| 1 | Cuisines | `SET_TASTE_TAG …'liked'` | `liked_tag_ids` |
| 2 | Spice | `SET_TASTE_TAG spicy …` | `liked_` / `disliked_tag_ids` |
| 3 | Sweet | `SET_TASTE_TAG sweet …` | `liked_` / `disliked_tag_ids` |
| 4 | Cooking style | `SET_TASTE_TAG prep …'liked'` | `liked_tag_ids` |
| 5 | Hero ingredients | `SET_TASTE_INGREDIENT …` | `liked_` / `disliked_ingredient_ids` |
| 6 | Restrictions | (existing preset/avoid flow) | `avoid_*`, `selectedPresetSlugs` |

---

## Analytics

- Keep firing `profile_set { taste_signal_count }` on submit (web + mobile, as today).
- **Add quiz funnel instrumentation** (the activation canary): furthest screen
  reached + completed-vs-skipped. Onboarding fatigue is the #1 risk; we must see
  where people drop.
- **Instrument `rec_acceptance`** downstream (tap/save on a Top Pick) — the
  discovery-quality metric from §7. A pretty quiz that yields bad picks is worse
  than no quiz.
- Taste prefs (cuisine/flavor) are **not** health data, so per-family counts
  (`liked_cuisine_count`, etc.) are safe to add if we want finer funnels — unlike
  the dietary profile, which stays off identified events.

---

## Build checklist

- [ ] Expand `flavor` taxonomy (+ optional `texture`/`format` family) — *quality prereq*
- [ ] Add `SET_TASTE_TAG` / `SET_TASTE_INGREDIENT` reducer actions + reducer tests
- [ ] `fetchTags(['cuisine','prep','flavor'])` in the quiz path
- [ ] Curate the hero-ingredient preset deck (seed-backed slugs)
- [ ] Build the 6 screens (web `apps/web/src/app/onboarding`, mirror in mobile)
- [ ] **Reorder onboarding so the quiz is step 1**; dietary → optional setting (§7)
- [ ] Quiz-funnel + `rec_acceptance` analytics
- [ ] Skip-after-screen-3 logic + minimum-viable-profile save

## v2 (fast-follow, not v1) — "this or that" dish swipe

Show two real dish photos: **"Which would you order?"** Infer taste tags from the
chosen `item.tag_ids`. More delightful and higher-signal, but needs a **curated,
representative dish set per tag** (cold-start), so it ships after v1's
chip/scale quiz proves the engine converts.
