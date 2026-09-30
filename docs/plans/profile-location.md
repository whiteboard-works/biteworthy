# Profile location — "X food nearby"

**Status:** P1 (home city) shipped 2026-09-30; P2 (device location per
turn) shipped for web 2026-09-30, mobile and the results-pane distance
still open.

## Goal

"What's good for vegan nearby?" gets an answer without the model asking
"which city?" first.

**Before P1** (the motivation, now history): `search_restaurants` needed a
`city_slug` for any listing or ranking, the profile stored nothing about
where the person is, and the prompt's volatile block only knew a
restaurant slug when the chat was opened from a restaurant page.
**Since P1** (2026-09-30): the profile holds `home_city_id`, the prompt
names it, and a listing or diet ranking with no `city_slug` defaults to it
for a credential that can read the profile. P2 makes "nearby" mean
distance within a city.

## What exists

- `cities.latitude/longitude` and `addresses.latitude/longitude` are in
  the schema (`db/schema.rb`); `list_cities` and `search_restaurants`
  already scope by city. **Unverified:** how many production addresses
  actually carry coordinates — check with `/sb-prod-query` before P2
  promises distance.
- `user_profiles.home_city_id` (P1, 2026-09-30) is the only location the
  profile holds: a city, never coordinates. `Tools::Profile::Serializer`
  and `ProfilePayload` carry it as `home_city`; any precise field P3 adds
  has to appear in both the same way.
- The page-context block already says "treat this as context for what
  *here* means"; it is the right carrier for a per-turn device location.
- Mobile deferred "near me" pending `expo-location`
  (`apps/mobile/app/index.tsx`).
- Legal: location is personal data. Stored coordinates need a
  `/privacy` line and must never ride on an analytics event
  (`packages/analytics` contract).

## Approaches

**A. Home city on the profile.** `user_profiles.home_city_id` (FK to
cities, nullable). Set from onboarding/settings (a picker over
`list_cities`) or in chat (`set_home_city`, or a `city` argument on the
existing profile update). `search_restaurants` defaults `city_slug` to
it when omitted; the profile snapshot in the prompt names it. No
geocoding, no coordinates stored, one migration. Honest about what
"nearby" means while there are two cities. Does not rank by distance.

**B. Precise location on the profile.** `latitude/longitude/label` on the
profile, set from browser geolocation or a typed address (needs a
geocoder), plus distance ranking in `search_restaurants` (haversine over
`addresses`, `distance_km` on results). Real "nearby", but stores
precise personal data, adds a third-party dependency for typed
addresses, and depends on address coordinates being populated.

**C. Device location per turn, not stored.** `PageContext` gains
`lat/lng` when the person allows it on `/chat`; the prompt's page block
says where they are; `search_restaurants` takes `near: {lat, lng}` and
ranks by distance. Nothing on the profile, nothing to disclose beyond
"sent with your message when you allow it"; forgotten when the tab
closes.

**Recommendation: A, then C.** A is the stored profile field the ask
names and costs one migration; C is what makes "nearby" true within a
city and needs no storage. B only if people ask to *save* a place that
is not a city ("near my office") — then it is C's payload persisted
behind an explicit "remember this".

## Phases

### P1 — home city (shipped 2026-09-30)

- Migration: `user_profiles.home_city_id uuid` (nullable, FK, index).
- `UserProfile belongs_to :home_city, optional: true`.
- `Tools::Profile::Serializer` + `ProfilePayload` gain `home_city`
  `{slug, name, region}`; profiles controller permits `home_city_slug`.
- New tool `set_home_city(city_slug)` (`audience :user`, not
  destructive, `running_description`, its own `pane` = none), or a
  `home_city` argument on `update_avoid_lists` — separate tool reads
  better in the catalog.
- `search_restaurants`: `city_slug` omitted → the caller's home city
  when signed in; the description says so. Ranking by `diet` then works
  with no city argument. The result echoes `city` and `city_source`
  (`argument` / `home_city`) so an empty answer is never mistaken for
  "nowhere", and `anywhere: true` opts out of the default.
- Prompt snapshot (`SystemPrompt#caller_section`) names the home city.
- Web: a "Home city" row in `/profile/settings` Dietary preferences; an
  optional onboarding step only if the picker is one select — otherwise
  settings + chat is enough for P1.
- ~~Privacy page: one line under what the profile stores.~~ **Deferred**
  by owner decision (2026-09-30): the `/privacy` wording is held for the
  L1 attorney sign-off; both sentences that need updating are listed in
  `docs/plans/chat-privacy-l1-brief.md`.
- rswag + openapi + api-types; specs for the default in
  `search_restaurants`, the serializer, and the tool.

### P2 — device location per turn (web shipped 2026-09-30)

**As built**, where it differs from the sketch below: the coordinates
never reach the model. `PageContext.location` rides the turn into
`Tools::Context#device_location` (`Chat::DeviceLocation` parses and
rounds it to three decimals); the prompt says only that a location was
shared; `search_restaurants` takes `near_me: true` + `radius_km` rather
than a `near: {lat, lng}` the model would copy into a stored tool_use
block. With no `city_slug`, `near_me` keeps restaurants within the radius,
plus those without coordinates whose city is within it (listed last,
`distance_km: null`), so a thin address backfill reads as "distance
unknown", not "nothing nearby". A diet ranking with `near_me` ranks in
the city of the nearest published restaurant (by address, or its city's
centre when it has none), not the nearest city centre: centres are unset
for cities added through `Cities::Create`. The bounding box wraps at
±180°. Not done yet: the results pane (its `restaurants` kind
is still on the pane branch), mobile `expo-location`, and a production
count of addresses with coordinates.

- `PageContext` gains `lat`, `lng`, `accuracy_m`; a "Use my location"
  control in the chat composer (browser Geolocation API, permission
  prompt, remembered per browser in `localStorage`).
- `SystemPrompt#page_section` says "The caller is at ~lat,lng (±m)".
- `search_restaurants` accepts `near: {lat, lng}` and `radius_km`,
  orders by haversine over `addresses.latitude/longitude`, returns
  `distance_km`; restaurants without coordinates sort last and say so.
- The results pane's `restaurants` kind (pane P2) shows distance.
- Mobile: `expo-location` behind the same `near` argument — the
  deferred "near me" sort on the home screen comes for free.

### P3 — remembered places (only if asked)

- Persist a C payload with a label behind an explicit "remember this";
  privacy copy for stored coordinates; delete-with-account already
  cascades through the profile.

## Out of scope

Geocoding typed addresses, a map view, multi-city expansion itself
(that is the multi-city roadmap item).

## Traps

- **Do not put location on analytics events.** `profile_set` and friends
  are a dashboard contract and the legal E7 shape; a city slug is not a
  health field but it is still personal, and nothing needs it there.
- **Home city is a default, not a filter.** A person in Salt Lake City
  asking about a Durango restaurant by name must still get it:
  `query` without `city_slug` searches everywhere; only the *listing*
  case defaults to home.
- **Distance needs coordinates.** Verify production address coverage
  before P2's description promises "nearest first".
