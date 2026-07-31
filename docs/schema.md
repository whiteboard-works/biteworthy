# Schema overview

The v2 data model lives in `apps/api/db/migrate/`. This is a 60-second tour.

## Identity

- `users` — Devise-backed (email + JWT), Apple/Google OAuth via `provider`
  + `uid`. UUID PKs throughout. `email` is `citext`, so uniqueness holds
  across case even on the write paths Devise doesn't own
  (`from_omniauth`, admin creates, seeds).
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
  `tag_ids uuid[]`. The Active Record join models (`ItemIngredient`,
  `ItemTag`) keep these in sync via after_save / after_destroy
  callbacks. The arrays are what the filter and the taste scorer read;
  the join tables are the source of truth + audit log.
- `item_variants` — sized pricing.
- `item_modifiers` — choices/additions/sides collapsed into one table.
  Ingestion writes these: a staged item's `addons_payload` promotes to
  `kind: "addition"` rows on accept.

Each join row carries `confidence` (`confirmed | suggested | inferred`)
and `source` (`human | ai | owner`). This powers strict-mode honest
disclosure: *we know X, we suspect Y, we inferred Z*.

## Enum columns

Every enum-ish column is a plain `string` whose allowed values live in
a model constant (`Item::STATUSES`, `ItemTag::SOURCES`, …) — there are
no Postgres enum types. Since Rails validations don't survive
`update_all` / `update_columns` / `upsert_all`, each one is also backed
by a validated `CHECK` constraint named `<table>_<column>_valid`.
`spec/models/enum_check_constraints_spec.rb` fails if a
model constant and its constraint drift apart — **widen the constant
and you must ship a migration widening the constraint in the same PR**.

## Reviews + community

- `reviews` — per-item, 1–5 + body. Unique on `[user_id, item_id]`.
- `suggestions` — polymorphic edit proposals queue. Replaces the 2020
  points/levels gamification with a real moderation pipeline.

## Ingestion

- `ingestion_runs` — state machine: `queued → extracting → resolving →
  staged → published` (or `failed`). Tracks model used + cost.
- `ingestion_items` — staged items waiting on contributor decisions
  (`pending | accepted | rejected | edited`). `addons_payload` holds
  nested add-on/upsell lines (`{name, price_cents, source}`).

## The filter (Phase 3 punchline)

The filter does **not** run in SQL, and it never removes rows. The read
path is:

```ruby
# ItemsController#index — apps/api/app/controllers/api/v1/items_controller.rb
restaurant.items.published
          .includes(menu_section: :menu, photo_attachment: :blob)
          .order(popularity: :desc, name: :asc)
```

…then, per item, in Ruby:

```ruby
(item.denormalized_ingredient_ids & filter.avoid_ingredient_ids)  # → avoid_ingredient
(item.denormalized_tag_ids        & filter.avoid_tag_ids)         # → avoid_tag
filter.strictness == "strict" && item.confidence != "confirmed"   # → unconfirmed_strict
```

`denormalized_*` and not `item.ingredient_ids`: the latter resolves to
the has_many-through reader, which **shadows** the identically-named
column and fires a query per item per association. A spec in
`spec/requests/api/v1/restaurants/items_spec.rb` fails if a read path
here starts touching `item_ingredients` / `item_tags` again.

An item with a non-empty `reasons[]` serializes as `status: "hidden"`
and carries the reasons. **That is deliberate**: honest disclosure means
a hidden item has to be able to say why, so it can't be filtered out in
the WHERE clause. A menu is tens-to-hundreds of rows, so loading all of
them is the cheap option anyway.

Ranking is a separate query. `TasteScoring.scores_for` (see
`app/services/taste_scoring.rb`) computes, for every published item at
the restaurant:

```
score = 2.0 * |tag_ids ∩ liked_tag_ids|
      + 1.0 * |ingredient_ids ∩ liked_ingredient_ids|
      - 2.0 * |tag_ids ∩ disliked_tag_ids|
      - 1.0 * |ingredient_ids ∩ disliked_ingredient_ids|
      + 0.5 * popularity / max_popularity_at_restaurant
      + 0.5 * (avg_visible_rating - 3) / 2
```

It only runs for a signed-in user with taste signals; everyone else
keeps the `popularity DESC, name ASC` order. Scores reorder and
highlight — they never hide. Note that `user_profiles.prefer_tag_ids`
is **not** an input to any of this.

The array-overlap SQL the schema is shaped for does exist, one level
up: `Cities::RestaurantRanking` ranks a city's restaurants by how many
dishes survive a preset, using

```sql
COUNT(items.id) FILTER (
  WHERE items.status = 'published'
    AND NOT (items.ingredient_ids && ARRAY[…]::uuid[])
    AND NOT (items.tag_ids        && ARRAY[…]::uuid[])
)
```

`&&` is Postgres's array-overlap operator. That one query replaces 30
calls to the items endpoint during SEO page SSR.

The filter computation is mirrored client-side by `applyProfile` in
`packages/filter-engine/src/index.ts`, and the scorer by `scoreItem` in
`packages/filter-engine/src/taste.ts` (shared fixture:
`fixtures/taste-parity.json`). All are tested; all must change
together.
