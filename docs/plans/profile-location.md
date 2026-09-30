# Profile location — "X food nearby"

**Status:** P1 (home city) shipped 2026-09-30; P2 next.

## Goal

"What's good for vegan nearby?" gets an answer without the model asking
"which city?" first. Today `search_restaurants` needs a `city_slug`, the
profile stores nothing about where the person is, and the prompt's
volatile block (`Chat::SystemPrompt#page_section`) only knows a
restaurant slug when the chat was opened from a restaurant page.

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
- Privacy page: one line under what the profile stores.
- rswag + openapi + api-types; specs for the default in
  `search_restaurants`, the serializer, and the tool.

### P2 — device location per turn

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
