# Chat results pane

**Status:** active, 2026-09-29. P1 shipped; P2 is next.

## Goal

The chat stops being a transcript on its own. Beside it sits a results
pane that shows *what the assistant is acting on right now*: the filtered
menu it just read, the scan it started and the dishes that came out of it,
the restaurants it found, the profile it just changed. The transcript says
what happened; the pane shows it, using the same components the rest of
the site renders those things with.

Decisions taken 2026-09-29:

- **Where:** `/chat` gets a split view — transcript left, pane right, a
  toggle at phone width. A chat drawer over every page (the page itself as
  the pane) is the long-term direction and the pane components are built to
  be lifted there, but it is not this arc.
- **Data path — hybrid.** The server emits a small typed `pane` reference
  (kind + ids + summary counts); the web pane fetches the detail from the
  REST endpoints that already exist and renders with the existing
  components. Kinds without a REST endpoint inline their list.
- **Slow build-out, read-only first.** No actions in the pane until phase 3.
- Signed-in only, like `/chat` today.

## Why not derive the pane from the transcript

Every tool result is already stored in the transcript
(`Chat::AgentLoop#tool_result`) and served to the web as `text`
(`Chat::Serializer`), so a pane *could* parse it. Two things rule that out:
`Chat::Compaction` drops older tool results, so a long chat's pane would go
blank; and the model-facing payloads fence dish text in
`<untrusted-content>` tags and trim what a UI needs (`GetMenu.for_model`).
The pane reads the REST payloads the pages already trust.

## The contract

A tool that has something to show declares it, in the same place it
declares its progress sentence:

```ruby
running_description { |args| "Reading the menu at #{args[:restaurant]}" }
pane { |args, data| { kind: "menu", restaurant: data[:restaurant][:slug], ... } }
```

`Tools::Base.pane_for(args, data)` runs the block against the tool's own
successful `structuredContent`, never against model text, and never for
an `isError` result. It is tool-declared for the same reason
`running_description` is: what the pane shows is the server's account of
what happened, not the model's.

The loop emits `{ type: "pane", pane: {...} }` as a persisted
`ConversationEvent` right after a tool call succeeds, so a reconnect
replays it, and writes the same hash to `conversations.last_pane` so
opening an old chat restores what it was last looking at. The show
endpoint serves it as `Conversation.pane`.

A successful **write** with no pane of its own re-emits the current
`last_pane` unchanged (`AgentLoop#show`). The web counts every live pane
event (`revision`) and refetches on each, so `update_avoid_lists` or
`set_strictness` redraws the menu on screen under the new filter instead
of leaving "you can eat" labels from the old one. Reads with no pane
(`get_restaurant`) do not re-emit.

`ChatPane` is a flat bag keyed on `kind` (like `ChatEvent`), so adding a
kind is additive for every client. Mobile ignores event types it does not
know (`describe` in `apps/mobile/app/chat.tsx` falls through), and this
arc does not add a mobile pane.

| kind | reference | pane fetches | renders with |
| --- | --- | --- | --- |
| `menu` | `restaurant` slug, `preset`, `strictness`, `visible_count`, `hidden_count` | `fetchRestaurantItemsClient` | compact rows + `HiddenReasonChip` |
| `scan` | `scan_id`, `status`, `restaurant` | `getScan` | read-only dish rows, polled while extracting |

`SectionBlock` was the first idea for the menu and was dropped: its grid
is sized to the viewport (`lg:grid-cols-3`), so inside a 26rem pane it
draws three cramped columns. The pane has dense rows of its own and
reuses the reason chip, which is the part that carries the contract.

## Phases

### P1 — contract + shell (shipped 2026-09-29)

- [x] `Tools::Base.pane` / `pane_for`, mirroring `running_description`'s
      inheritance and rescue.
- [x] `pane` declared on `get_menu` (menu) and once on
      `Tools::Ingestion::Base` for all seven scan tools;
      `edit_staged_item` / `undo_staged_item` now return `scan_id` so
      theirs resolves.
- [x] `AgentLoop#execute` emits the `pane` event (between `tool_use` and
      `tool_result`) and writes `last_pane`.
- [x] Migration: `conversations.last_pane jsonb`, nullable.
- [x] `Chat::Serializer` serves `pane` beside `messages`; rswag `ChatPane`
      schema, `Conversation.pane`, `ChatEvent.pane`; openapi + api-types
      regenerated.
- [x] Web: `_ResultsPane.tsx`; split layout on `/chat`; live `pane` event
      swaps the pane (a revision counter makes an identical reference —
      an accept on the scan already listed — refetch too); opening a chat
      restores `conversation.pane`; "Results" toggle under `lg`; the
      running tool's sentence as the pane's status line.
- [x] Tests: loop emits + stores the pane and skips it on failure;
      `pane_for` contains a raising block; pane renders a menu and a scan
      from mocked fetchers and polls an unfinished scan; ChatClient swaps
      the pane on the event, restores it on open, clears it on new.

### P2 — more kinds + "acted upon"

- `restaurants` (search results, inlined), `restaurant` (`get_restaurant`),
  `profile` (`get_profile` / `update_avoid_lists` / `set_strictness`
  refetch the profile), `item` (`explain_item` / `edit_item`).
- Highlight what the last write touched: ids from the tool input/result
  ride on the pane reference; the menu view marks those rows.

### P3 — the pane talks back

- Click a dish → next message carries it as page context (`PageContext`
  gains `item`).
- Accept / reject staged dishes from the pane through the REST scan door.
- Chat opened from a restaurant page preloads that menu (`pageContext()`
  already carries the slug).

## Out of scope

Mobile UI, new tools, the M7 REST adapters, the chat-drawer-on-every-page
direction.

## Traps

- **Do not render model-facing payloads.** They are fenced and trimmed for
  the model. Fetch the REST shape.
- **The pane fetch uses the same filter the tool used.** `get_menu` may
  have previewed a preset (`diet:`) or overridden strictness; the reference
  carries both so the pane shows the menu the assistant is talking about,
  not the user's saved one.
- **Both doors filter the same way.** `get_menu` and the REST items
  endpoint both call `Menus::Filter.build` with the signed-in user, so a
  preset adds to their own avoids on either side. The pane still draws
  its counts from the list it fetched rather than from the tool's
  numbers, so a menu edited between the call and the fetch cannot make
  the pane contradict itself.
- **The pane sends only the model's overrides.** `get_menu`'s pane
  carries `diet` / `strictness` from the *arguments*, not the resolved
  filter, so a chat reopened after the person changed their profile
  draws today's menu, not a snapshot.
- **Dish links carry the pane's filter.** A menu pane drawn under
  `strictness: strict` links each dish with `?strictness=strict` (and the
  preset), and the dish page passes both to `fetchItem`, so the server
  judges the dish under the same filter the list was drawn with. Without
  it a dish hidden here as unconfirmed opens as visible under the saved
  strictness.
- **A scan pane retries its first look.** A chat reopened mid-scan gets no
  further pane event, so a first status request lost to a 429 or a 502
  is retried on the poll cadence, bounded to five failures in a row.
- **A pane event can arrive for a chat that is off screen.** Same rule as
  every other event in `_ChatClient`: only the chat being viewed draws it;
  the stored `last_pane` catches up on open.
