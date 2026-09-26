# MVP speed + UI pass (working todo, 2026-09-26)

Working list for the pass that came out of the 2026-09-26 whole-codebase
review. Tick items as their PRs merge; **delete this file in the last PR**
of the pass (the roadmap/status entries keep the history).

Scope decisions from Skylar: MCP stays whole; the cleanup/cut phase is
skipped ("who knows if those add value later"); mobile is **frozen** —
bug and speed fixes only, no new features; the drop-tables migration is
not happening.

One deliberate reversal of the MCP pivot, flagged per Rule 8: the pivot
replaced the swipe-verify UI with the chat. Scanning stays reachable
through chat and MCP, but the chat is not a good *only* door for the core
loop — every status poll is an Opus round, a slow scan can exhaust the
turn's iteration budget, and mobile never lands on the menu afterwards. So
a plain REST door and a scan screen come back, as thin adapters over the
same tools.

## Speed

- [x] 2.1 `POST /api/v1/scans`, `GET /api/v1/scans/:id`, `POST /api/v1/scans/:id/accept` — thin adapters over `start_menu_scan` / `get_scan_status` / `accept_staged_items`; status is a row read, never a model call
- [~] 2.2 ~~Retry transient extraction failures~~ — **dropped, premise was wrong.** `AnthropicClient` already retries 429/5xx and timeouts 3× in faraday-retry (`anthropic_client.rb:288-292`), and an exhausted timeout escapes `TimedAnthropicCall` into the job's `retry_on`. What still fails the run first time — truncation and schema-invalid output — would mostly fail the same way on a re-billed retry.
- [ ] 2.3 Menu read path: drop the unused `menu_section: :menu` preload (`Menus::Query#load_items`) + a query-budget spec. **Cache/ETag dropped**: measured 6 indexed statements anonymous, 12 signed in, constant in menu length — too cheap to be worth a cache that could serve a stale allergen correction.
- [ ] 2.4 Mobile (frozen, fixes only): no anonymous-then-authed double fetch on the restaurant screen; `expo-image` everywhere. **List virtualization skipped** — a restructure of a frozen screen for menus that render fine at their real size.

## UI

- [ ] 3.1 Web scan screen: photo/URL → progress → review grouped by section → Accept all → land on the filtered menu
- [ ] 3.2 Value before signup: surface `/durango` diet pages + a pre-filtered restaurant from the homepage; onboarding shrinks to preset + avoids, taste step after the first menu
- [ ] 3.3 Menu page: split `RestaurantClient.tsx`; Top Picks as the visual payoff with an explained empty state; strict mode says how many dishes are hidden as unconfirmed; new users default to balanced
- [ ] 3.4 Community → picks: favorites and the user's own ratings feed `TasteScoring`, so picks show without the taste quiz

## Out of scope

Chat lease/replay simplification, review-photo malware scanning, PostHog
ingestion, `docs/status.md` trim, item variants/modifiers, model-ID bumps.
