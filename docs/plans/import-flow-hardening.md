# Import-flow hardening (2026-10-12)

Living plan. Started from an agent-driven import of Riverton, UT restaurants
over MCP (Salsa Leedos, North Italia, Saffron Circle): every place the flow
put an unsafe dish in front of a filter, failed without saying why, or made
the reviewer do the pipeline's job. Each item says what was seen, then what
fixed it or what is still open.

## Allergen safety

- [x] Gap-fill dropped an invented slug with its allergen family (`dairy-grana-padano` ×6, `grain-wheat-flour` ×5): now falls back to the nearest catalog ancestor (#906).
- [x] Compound sauces carried no allergen (aioli → egg, hollandaise → egg + butter, pesto → parmesan + pine nuts, …): `Ingestion::IngredientImplications`, applied by the resolver and gap-fill (#907), enforced again at accept for scans staged before it or retried (#915), with a backfill for live dishes (#910).
- [ ] **Run the live-dish backfill** (human): `bin/rails biteworthy:menus:backfill_sauce_allergens` dry run, review the list, then `--env APPLY:1`.
- [x] Bare "cheese" matched nothing: alias on `dairy`, plus Grana Padano / Stracciatella / Scamorza nodes (#909); "dairy-free" matched the `dairy` root by its own name, so absence phrases are consumed as leftovers (#909), unless negated or offering a variant (#916).
- [x] Plural "olives"/"cloves" never matched (ActiveSupport's knives → knife rule): trailing-"s" fallback (#908); "garlic cloves" then matched the clove spice: alias on garlic (#916).
- [x] False friends: bare "french"/"italian" dressing aliases retired, plural "peppers" → bell pepper (#912); ginger beer as soda, "glazed nuts" → Mixed Nuts implying peanut, carne asada → beef, chicken fried steak → breaded beef (catalog PR).
- [x] A staged edit kept stale allergen tags and restamped kept AI rows as human (#914).
- [ ] Remaining matcher false friends seen once: "sweet pork" → tag `sweet`, "crab meat" → generic `meat`, "creamy fish sauce" → fish sauce, "est. 1885 – bologna" → mortadella, "lemon curd" → curds. All over-hide; worth a stop-list or context rule if they recur.
- [ ] A name-level diet claim ignores "option": `DietClaims` treats "Walnut Brownie (nut free option)" as a nut-free dish and suppresses walnut from the name scan. Make the claim variant-aware, as the matcher's absence phrases are (#916).
- [ ] A dish whose payload ends up empty is shown to everyone as safe. Consider flagging zero-ingredient dishes in `needs_attention` and refusing to accept them without a human edit.
- [ ] `jev_wheat_shadow` disagreements (e.g. Italian Meatballs: Jev 0.76 wheat, data none) are logged but never surfaced; put them in `needs_attention`.

## Scans that fail or mislead

- [x] A 2.2 MB Wix page failed with "prompt is too long: 1068223 tokens": fetched HTML is reduced to visible text + menu JSON-LD, and a page with no dishes fails as `no_dishes_found` (#911, charset follow-ups #913, #919).
- [x] Tools promised 20–60 s (real PDFs: 25–108 s plus enrichment); a failed run reported enrichment pending forever (#917).
- [x] Parallel scans of one restaurant doubled shared dishes: accept holds a late exact match for review instead (#918).
- [ ] **Gap-fill is not grammar-constrained.** It validates `response_schema` after the fact but sends no `output_config`, so a misplaced `unresolved` field failed whole slices (run 74b999be, twice). Add `output_config` as `ExtractRun` does; needs the gap-fill VCR cassette re-recorded with a live `ANTHROPIC_API_KEY` (human).
- [ ] A stale or group-wide menu PDF (Saffron Circle's "Riverton takeout menu" lists a closed location) stages without warning. Flag a source that names other locations or carries an old date.
- [ ] `discover_restaurant_site` finds no addresses on Squarespace/Wix sites whose locations are plain text, and silently follows a redirect to one location's page (asked for `/hours-locations`, got `/vancouver`).
- [ ] A site with several menu pages (lunch, brunch, kids) needs one scan per page; there is no multi-URL scan.

## Throughput and access

- [x] Reviewing a 185-dish scan filled an agent's context: `list_staged_items compact: true`.
- [ ] One Solid Queue process with `threads: 3` on `queues: "*"`: four parallel scans queued behind each other and share threads with chat. Consider a dedicated ingestion worker or concurrency limits.
- [ ] Toast-only restaurants (Saffron Circle, Seoul Meat Co) cannot be imported by an agent: HostPolicy refuses Toast (correctly, for ToS) and MCP has no upload path, so photos/PDFs must come from a person.
- [ ] MCP cannot attach dish photos: `set_item_photo`/`submit_dish_photo` need an app-upload attachment id.

## Decisions for a person

- [ ] An admin's accept records every association as `confirmed`, so an agent with an admin token publishes model output to strict-mode (allergy) users. Should admin accepts made over MCP record `suggested` unless a person confirms?
- [ ] Should `tree_nut` / `dairy` presets also avoid by `contains-*` tag for dishes whose tags were edited by hand? (Presets hide by ingredient path today; tags are display.)

## Reading the logs

Production logs reach PostHog (service `Biteworthy`). Every ingestion line
carries the run id, so `query-logs` with `searchTerm: "<scan_id>"` returns a
run's `[jev_cuisine]` and `[jev_wheat_shadow]` lines, and `searchTerm:
"ExtractMenuJob"` gives each job's enqueue/perform/duration. Warnings worth
watching: `GapFillResolveJob: dropping unknown ingredient slug` (now rare,
see #906) and `gap_fill_validation_failed`.
