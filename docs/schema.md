# Schema overview

The v2 data model lives in `apps/api/db/migrate/`. This is a 60-second tour.

## Identity

- `users` — Devise-backed (email + JWT), Apple/Google OAuth via `provider`
  + `uid`. UUID PKs throughout.
- `user_profiles` — one per user. `avoid_ingredient_ids[]`,
  `avoid_tag_ids[]`, `prefer_tag_ids[]`, plus `strictness` enum.

## Taxonomy (the unique-value engine)

- `ingredients` — hierarchical via `path ltree`. Closed catalog: only
  admins/AI-pending-review can add nodes. `aliases[]` lets "garbanzo"
  resolve to "chickpea". `allergen` flag drives the strict-mode UI.
- `tags` — also hierarchical via `path ltree`. Five families:
  `diet`, `allergen`, `cuisine`, `prep`, `flavor`.
- `dietary_profiles` — curated bundles (Celiac, Vegan, Halal, ...) that
  pre-fill a UserProfile in one tap.

## Place

- `cities` → `restaurants` → `addresses`, `hours`. No more "Durango"
  default — every restaurant lives in an explicit city.

## Menu

- `menus` → `menu_sections` → `items`.
- `items` carry **denormalized arrays**: `ingredient_ids uuid[]`,
  `tag_ids uuid[]`. Both have GIN indexes. The Active Record join models
  (`ItemIngredient`, `ItemTag`) keep these in sync via after_save /
  after_destroy callbacks. The arrays are what the filter query hits;
  the join tables are the source of truth + audit log.
- `item_variants` — sized pricing.
- `item_modifiers` — choices/additions/sides collapsed into one table.

Each join row carries `confidence` (`confirmed | suggested | inferred`)
and `source` (`human | ai | owner`). This powers strict-mode honest
disclosure: *we know X, we suspect Y, we inferred Z*.

## Reviews + community

- `reviews` — per-item, 1–5 + body. Unique on `[user_id, item_id]`.
- `suggestions` — polymorphic edit proposals queue. Replaces the 2020
  points/levels gamification with a real moderation pipeline.

## Ingestion

- `ingestion_runs` — state machine: `queued → extracting → resolving →
  staged → published` (or `failed`). Tracks model used + cost.
- `ingestion_items` — staged items waiting on contributor decisions
  (`pending | accepted | rejected | edited`).

## The filter query (Phase 3 punchline)

```sql
SELECT items.*
FROM items
WHERE items.restaurant_id = $1
  AND items.status = 'published'
  AND NOT (items.ingredient_ids && $avoid_ingredients_uuid_array)
  AND NOT (items.tag_ids        && $avoid_tags_uuid_array)
  AND ($strictness <> 'strict' OR items.confidence = 'confirmed')
ORDER BY
  cardinality(items.tag_ids & $prefer_tags_uuid_array) DESC,
  items.popularity DESC;
```

`&&` is Postgres's "array overlap" operator and uses the GIN index. This
is the entire reason the schema looks the way it does.

The same shape lives in `packages/filter-engine/src/index.ts` for the
client side; both are tested.
