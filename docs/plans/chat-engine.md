# Chat engine — hardening the loop into a system

Living plan. Started 2026-08-08, after M5. Mechanics live in
[`docs/mcp.md`](../mcp.md); the tool layer's own arc is
[`mcp-pivot.md`](mcp-pivot.md). Phase checkboxes mirror `docs/roadmap.md`.

## Why

The MCP pivot shipped a chat that works: `Chat::AgentLoop` on
`claude-opus-5`, 44 tools behind one audience filter, a server-side
confirmation gate, SSE turns, and a UI. The first live run proved the prompt
cache holds (21,650 tokens read per turn) and that an injected dish
description does not cause a tool call. It also produced the first cost
number: **~8.5¢ per turn**.

What it does not have is the layer around the loop. A turn runs inline in
`ActionController::Live`, so it holds a Puma thread for its whole life and
dies with the request. There is no lock — two tabs interleave. There is no
abort, no per-round metrics, and no persisted record of a failure: an error
exists only as an SSE event and vanishes on the client's next refetch.

The framing that produced this plan: **the agentic chat loop is a
distributed-systems problem — locks, leases, replay invariants, idempotent
repair — not a prompt wrapper.** Each phase below takes one failure mode
that currently has no owner and gives it a tested path to a coherent UX.

## Constraints that shape every decision

- **No Redis.** One Hetzner VM, Neon Postgres, Solid Queue / Cache / Cable.
  Locks, leases, abort flags, and the pending queue are Postgres rows, not
  KV entries.
- **The tool layer is the command layer.** Anything that guards one front
  door and not the other is a divergence waiting to happen.
- **Honest disclosure is the product.** A hidden dish must always be able to
  say why. Every safety mechanism here serves that claim.
- Not in production — closed beta, two users. Breaking changes are cheap;
  compatibility shims are not worth their weight.

## Decisions

| # | Decision | Why |
|---|---|---|
| C-D1 | Locks, leases, and the pending queue live in Postgres, not Redis | No Redis in the stack and no reason to add an accessory for one feature. A conditional `UPDATE … WHERE run_token = ?` is a compare-and-set; a partial unique index is a mutex. |
| C-D2 | Arguments are validated in `Tools::Base`, not at each call site | The MCP door validated and the chat door did not, so an invented argument name reached the model as "cannot be retried" — a lie it could have fixed in one round. |
| C-D3 | A tool bug returns `tool_failed`, it does not raise | A bug must not kill a conversation, and must not read as a recoverable domain error either. The distinct code is what tells the model to stop rather than to rewrite its arguments. |
| C-D4 | Confirmation binds to the exact `{tool, args}` tuple | The gate is only as good as what it is bound to. A model-supplied `confirmed: true` is not evidence, and neither is a stale tab's approval of a call it no longer displays. |
| C-D5 | `defer_loading` over a homegrown tool router | Tools render *before* system in the cached prefix, so a per-turn tool bundle busts the whole 21,650-token cache on every routing change. Deferral appends and preserves it. |
| C-D6 | Grounding review appends a disclaimer; it does not retry | Latency is already a minute. A second full turn to fix a partially-right answer costs more than saying plainly that the answer may be incomplete. |

## Safety properties

Invariants, not features. A change that breaks one is a bug even if the
suite is green.

1. **Nothing escapes `Tools::Base.call`.** Both front doors get the same
   authorization, the same validation, and the same error shapes.
2. **A destructive call is answered by a human, for that exact call.**
   Confirming one does not pre-authorize the next, and an answer that does
   not match the parked call is rejected.
3. **Every `tool_use` gets a `tool_result`.** The Messages API rejects a
   transcript where one does not, which makes an unanswered call a
   permanently dead conversation rather than one lost turn.
4. **Every failure is a record, not just an event.** An error the user saw
   must survive their next reload.
5. **An avoid-list removal is gated by code, not by prose.** It un-hides
   dishes, which is the direction that can hurt someone.

---

## Phases

### C1 — One tool boundary, not two — SHIPPED

`Tools::Base.call` is now the single place a tool call is authorized,
validated, dispatched, and rescued.

- **Arguments validated before dispatch**, against the declared
  `input_schema` *and* the real `perform` signature. Neither subsumes the
  other: the schema knows types and required-ness; only the signature knows
  which keywords `perform` will accept. All problems report in one message.
- **`StandardError` contained as `tool_failed`.** `Chat::AgentLoop#execute`
  dropped its own rescue — a second one at the call site is exactly how the
  doors drift.
- **Six admin multiplexers declare `additionalProperties: false`.** Their
  `perform` takes `**args`, so the signature cannot tell a real keyword from
  an invented one and the schema has to.

Traps hit: `accepted_keywords` was memoized from `method(:perform)`, so a
test stub poisoned it for the rest of the process — the value is now read
fresh every call. And validating one problem class at a time made a model
with two mistakes spend two rounds; they report together.

Acceptance:
- [x] Every registered tool, through both doors, answers a malformed call
      with a recoverable `isError` and never raises
- [x] A tool that raises returns `tool_failed`, not a 500 and not `invalid`
- [x] An invented argument name is echoed back with the accepted list

### C2 — Confirmation bound to the call — SHIPPED

`update_avoid_lists` carried `destructive_hint: false`, so **removing an
allergen was gated only by prose in `Tools::Instructions`** — a
model-enforced boundary on the one operation whose failure mode is someone
eating something that hurts them.

- `confirm_when { |args| … }` on `Tools::Base`, evaluated alongside
  `destructive_hint`, so a call can be dangerous in one direction only.
  Removals park; adds and presets stay frictionless, because friction on
  the safe direction is how people stop declaring allergens at all.
- `confirmation_prompt { |args| … }` — the sentence a person approves is
  declared by the tool, not phrased by the model asking for the approval.
  The client falls back to its generic prompt when a tool declares none.
- `park` computes a fingerprint of `{name, input}` **once** and stores it;
  `/confirm` must echo it back. Deliberately not recomputed from the parked
  row — jsonb does not preserve key order, so a hash derived from the
  round trip would not reliably match one derived from the live call.
  **Fails closed**: a missing stored fingerprint is a mismatch, not a pass.
  "Absent means allowed" is how a check like this quietly stops checking.
- Both declarations walk the superclass chain, for the same reason
  `audience` does: Ruby does not inherit class-level ivars, and the last
  time that was missed a domain base's declaration silently did nothing.
- The server instructions now say the gate exists rather than asking the
  model to police itself, so it announces the removal and expects a pause.

### C3 — Run lifecycle: lock, lease, abort, metrics — SHIPPED

`conversation_runs` — `run_token`, `state`, `lease_expires_at`,
`abort_requested_at`, per-round token counts, outcome, duration. Three
Postgres primitives standing in for what Redis would have done:

- **The lock** is a partial unique index on `conversation_id WHERE state =
  'running'`. A second `INSERT` loses instead of interleaving two
  transcripts into one ordered message list — which is not merely
  confusing, it is rejected by the Messages API, so the conversation
  becomes permanently unusable rather than one turn poorer.
- **The lease** is `lease_expires_at`, refreshed at every lifecycle event.
  A worker killed mid-turn stops refreshing and the next turn steals the
  lock once it lapses. Without it one dead container wedges a conversation
  forever. The steal is a conditional `UPDATE`, not delete-then-insert, so
  two workers racing on the same lapsed lease produce one winner.
- **Ownership** is `run_token`, and every write is conditional on it. A run
  whose lease was stolen writes nothing when it comes back — it finds out
  it was replaced rather than clobbering its replacement.

`tick!` refreshes the lease and reads the stop flag in one statement, at
every checkpoint: before each model call and around each tool. A turn is a
minute of work, and a stop button honoured only at the end is not a stop
button. The flag is compared against `started_at`, so an abort raised for
an earlier run can never kill a newer one, and a steal clears it.

Failure paths became records rather than events: an abort answers the tool
call it abandoned (an unanswered `tool_use` refuses the whole conversation
from then on), persists the apology so a reload still shows it, and leaves
the conversation `active`. `heal!` prunes empty assistant messages at run
start — `content: []` replays as a 400.

`DELETE /conversations/:id/run` raises the flag. It lives on
`ConversationsController`, not the streaming one: `ActionController::Live`
rewrites the response object for every action in its controller, and the
stop has to be a separate request from the turn it stops anyway.

**Deferred to C4: the pending queue.** `pending_turn` only pays for itself
once a job can consume it and re-enqueue; with the turn still inline there
is nothing to hand the queued message to, so a second turn is refused
outright rather than queued.

### C4 — Turns run in a job; SSE becomes a relay — SHIPPED

- `POST /messages` and `/confirm` record the request and enqueue
  `Chat::CompletionJob`, then return `202` with the narration position to
  watch from. No LLM work in the request cycle.
- **The queue holds requests, not messages.** A user message appended to
  the transcript at request time would land in the middle of a running
  turn's message list — and that turn would then answer it. `pending_turns`
  holds the ask as data; the job appends it as a message only once it holds
  the lock. One serialization point, and no race between checking whether a
  run is active and writing.
- `conversation_events` is the narration as rows. `GET /stream` tails it
  and honours `Last-Event-ID` (or `?after=`), so a reconnect **resumes**
  rather than waiting blind for the turn to end and refetching.
- `EventWriter` coalesces text deltas — 80 chars or 150ms, whichever comes
  first. A row per token would be tens of thousands of inserts per answer.
- The job drains the whole queue before releasing, so rapid-fire messages
  serialize instead of racing and none are dropped. The release happens
  before the final queue check, which is what closes the race where a
  message enqueued mid-turn would otherwise be stranded.
- `AgentLoop` takes an injected `run:` so the job can own the lock — it
  needs the run before the turn starts, because every event row is stamped
  with it. A direct caller passing nothing still acquires and releases
  inside the loop.
- Web: ask, then watch. Stop button wired to `DELETE /run`.

Trade-off taken deliberately: text arrives in ~150ms chunks instead of per
token. In exchange a turn survives a proxy timeout, a deploy, and a closed
laptop, and Puma threads stop being held for a minute at a time.

### C5 — Prompts as code, plus the volatile block — SHIPPED

`Chat::SystemPrompt` renders ordered sections: instructions → topology →
**cache breakpoint** → a trailing volatile block carrying the caller's
profile snapshot, the time, and the page context the client sent.

- **The invariant is not where the breakpoint sits, it is that nothing
  per-request sits above it.** The spec that pins it compares the whole
  cached prefix across two turns rather than asserting a position — a
  measured 21,650-token prefix is thrown away by one volatile byte in the
  wrong block, and a position assertion would not catch that.
- The profile snapshot is the payoff: most turns stop spending a
  `get_profile` round trip before they can answer anything. It says
  plainly that the tools outrank it, because a snapshot goes stale the
  moment the model edits the profile, and a model trusting it would report
  a change it just made as not having happened.
- Page context turns "what can I eat here" into one tool call instead of
  three. It is client-supplied, so it is labelled as context rather than
  instruction, and length-capped.
- Revoked access reads as a plain fact about the caller ("not signed in"),
  not as an exception.
- `bin/prompt-tokens` prints the split; two specs hold each side to a
  budget so a section cannot quietly double. The script aborts rather than
  reporting the anonymous prefix when `--admin` finds no admin —
  `Tools::Context` resolves the caller from the database, so an unsaved
  `User` reads as signed-out.

### C6 — Grounding review on dietary answers — SHIPPED

Safety Property 1 — *hidden dishes are returned with their reasons, never
dropped* — turned from an instruction into something enforced. Until now
it lived in `Tools::Instructions`, which is the model marking its own
homework: a summary that quietly omits the one dish someone is allergic to
reads exactly like a good answer.

After a turn whose tools included `get_menu` or `explain_item`, a tool-less
`claude-haiku-4-5` call gets the filter's own output and the assistant's
text and answers whether the answer omitted a hidden dish, contradicted a
`reasons[]`, or claimed a dish is safe. On a flag it appends a disclaimer
and marks the run `grounding_flagged`.

- **Fails open on infrastructure errors**, but never silently — a reviewer
  that is down must not take the chat with it.
- **Anything other than a literal `true` is a flag.** `"false"`, `"no"`,
  `nil`, `0` are each pinned by a spec, because every one of them is truthy
  if you ask the wrong way and each would wave through exactly the answer
  this exists to catch.
- **Appends rather than retries.** A turn is already a minute; a second
  full turn to repair a partly-right answer costs more than saying plainly
  that it may be incomplete.
- The flag is recorded as the run's `outcome` rather than written directly
  — `release!` owns that column and would otherwise overwrite it with
  `"done"`. (Found by the spec, not by reading.)

### C7 — Deferred tool loading and progress text — SHIPPED

**Deferred loading.** Most tools are now declared but not loaded. The core
domains — discovery, profile, meta — stay resident because they open nearly
every conversation and meta is the map to everything else; the rest carry
`defer_loading: true` and arrive via the server-side tool-search tool
(`tool_search_tool_regex_20251119`).

Measured on the real registry:

| Caller | Tools | Cold-turn schemas before | After | Saved |
|---|---|---|---|---|
| signed-in | 32 | ~8,556 tok | ~2,794 tok | **67%** |
| admin | 45 | ~13,232 tok | ~2,794 tok | **79%** |

Two ways to get this wrong both cost a 400 on *every* turn rather than a
worse answer, so both are asserted rather than trusted: the search tool
must never itself be deferred, and at least one tool must stay resident.
A spec stubs `CORE_DOMAINS` empty to prove the guard fires.

Regex search over BM25 because the names here are deliberate and
domain-prefixed (`edit_menu_structure`, `list_moderation_queue`) — a
pattern match is predictable in a way relevance scoring is not.

**Why deferral rather than a router we control.** Tool search *appends* the
schemas it finds instead of swapping the tool array. Tools render ahead of
system in the cached prefix, so a per-turn bundle of our own choosing would
throw away the whole 21,650-token cache every time the bundle changed.
Deferral keeps the prefix intact. This is the answer to the open question
C3's token columns were added to settle.

**Progress text.** `running_description` on a tool renders "Reading the
menu at Nini's" instead of `get_menu`. Declared by the tool and never
model-supplied: it is the only thing a person can read while a turn is
working, and a model narrating its own calls would describe what it intends
rather than what is happening. Clients fall back to the humanized name when
a tool declares nothing.

**Admin debug pills and chat analytics followed** in a separate PR: the
conversation payload carries a `usage` object for admins only (the server
decides, so the client has no visibility check to get wrong), and three
add-only events — `chat_started`, `chat_turn_completed`, `chat_confirmed`
— joined the taxonomy. Those events carry **no message text and no tool
names**: a tool name like `update_avoid_lists` on an identified event says
this account edited a dietary profile, which is the same health-adjacency
the taxonomy already strips from `profile_set`.

**Resource chips remain unbuilt**, and deliberately. Tool results carry
their payload as a JSON text blob, so chips would mean the client guessing
at each tool's response shape — brittle, and wrong the first time a tool
changes its output. The honest version is a per-tool declaration alongside
`running_description`, which is worth doing when someone wants the chips,
not before.

---

### C8 — Cost accounting that is not mostly rounding — SHIPPED

C3 added per-round token columns to answer "where is the money going".
They were right; the money figure beside them was not.

`Ingestion::UsageCost.cents` rounds **up per model call**. That is the
right call for an ingestion run (one or two calls, and a guardrail should
overstate — its comment says so) and wrong for a turn that makes up to
twelve. Measured on the real shape — twelve rounds re-reading the
21,650-token cached prefix on Opus 5 — the turn cost **13¢ and reported
24¢**. The ceiling therefore also fired early, which is why "the chat
limit is too small" and "24¢ for one question" were one bug.

- **Micro-cents are the stored truth**, via `UsageCost.micro_cents`. It is
  the same arithmetic without the final division, so nothing is
  estimated. `.cents` keeps its ceil for ingestion.
- **`conversations.api_cost_cents` is a GENERATED STORED column** derived
  from it. Two columns holding one fact is how they drift, and this fact
  gates spending. Enforcement compares micro to `ceiling × 1e6`, so there
  is no rounding left in the path that refuses a turn.
- **The grounding reviewer is billed.** It builds its own client, so its
  usage never reached the conversation — every grounded turn
  under-reported one haiku call. It accrues through `record_side_call!`,
  not `record_round!`, because `rounds` means loop iterations and a side
  call is not one.
- **`record_round!` is guarded by `run_token`**, like `tick!` and
  `release!` always were. It was the one accrual that could write onto a
  run that had already replaced it.
- The footer separates the two scopes it had been conflating:
  `9¢ turn · 34¢ conversation`, plus the `cache_write_tokens` C3 recorded
  and nothing displayed.

## Open questions

- **Whether the Postgres event relay is quiet enough at one poll per 200ms
  per open stream.** Fine for a closed beta; Solid Cable is the fallback.
- **What the grounding reviewer's false-flag rate is.** A disclaimer on
  every correct answer is its own failure mode.
- **Uploaded blobs are still never swept** (carried over from the pivot
  plan): an attachment uploaded and never scanned stays in storage forever.
