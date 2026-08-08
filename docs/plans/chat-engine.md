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

### C6 — Grounding review on dietary answers

Safety Property 1 made enforceable instead of instructed. After a turn whose
tools included `get_menu` or `explain_item`, a tool-less `claude-haiku-4-5`
call gets the filter's own output and the assistant's text and answers:
did it omit a hidden dish, contradict a `reasons[]`, or assert that a dish
is safe? Fails open on infrastructure errors; anything other than a literal
`true` counts as flagged (truthiness is the footgun). On flag, append a
disclaimer rather than retry.

### C7 — Routing, progress, and the metrics surface

M6's `defer_loading` + tool search, now measurable against C3's token
columns. `running_description` per tool so the transcript reads "Reading the
menu at Nini's" rather than `get_menu`. Resource chips from the ids tool
results already carry. Debug pills for admins. Chat events into
`packages/analytics` (add-only — renaming one breaks the launch funnels).

---

## Open questions

- **Whether the Postgres event relay is quiet enough at one poll per 200ms
  per open stream.** Fine for a closed beta; Solid Cable is the fallback.
- **What the grounding reviewer's false-flag rate is.** A disclaimer on
  every correct answer is its own failure mode.
- **Uploaded blobs are still never swept** (carried over from the pivot
  plan): an attachment uploaded and never scanned stays in storage forever.
