# _legacy/

Frozen archive of the 2020 BiteWorthy codebase: Rails 4.2.11 / Ruby 2.5.7,
last meaningfully touched in 2020 and never re-deployed after Heroku free
dynos retired in November 2022.

## Why it's still in the repo

This directory exists for **reference only**. The v2 rebuild
(`apps/api`, `apps/web`, `apps/mobile`) reuses the *ideas* — ingredient
hierarchy, tag taxonomy, item-as-recipe data model, dietary-filter goal —
but starts from a clean slate. The 2020 stack (Rails 4.2, Ruby 2.5,
Paperclip, Elasticsearch 6, Foundation 6, jQuery, CoffeeScript) is past
end-of-life and not worth upgrading in place.

## Rules

- Do **not** edit anything in here.
- Do **not** wire it into CI, deploys, or `pnpm` workspaces.
- Do **not** depend on it from new code.
- When porting an idea forward (e.g., the ingredient seed list at
  `_legacy/db/seeds/0_ingredients.rb`), copy the data into a new
  migration or seed file under `apps/api/`. Don't `require` from here.

## What's worth a second look

| File / dir | Why |
|---|---|
| `_legacy/db/schema.rb` | Original data model; informs `apps/api/db/schema.rb` |
| `_legacy/db/seeds/0_ingredients.rb` | Hand-curated ingredient list — port forward |
| `_legacy/app/models/ability.rb` | Original CanCan rules — informs new authz |
| `_legacy/app/views/pages/about.erb` | Original product pitch in the founder's words |
| `_legacy/app/models/user.rb` | The 14-tier level system (intentionally dropped in v2) |

If you find yourself reaching for anything else here, pause and ask
whether v2 actually needs it.
