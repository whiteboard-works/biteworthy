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

### C3 — Run lifecycle: lock, lease, abort, metrics

New `conversation_runs` table — `run_token`, `state`, `lease_expires_at`,
`abort_requested_at`, per-round token counts, outcome, duration. Partial
unique index on `conversation_id WHERE state = 'running'` is the mutex.

- Acquire by insert; steal an expired lease by conditional update.
- `tick` at every lifecycle event refreshes the lease and reads the abort
  flag in one statement: no rows → `LostLease`, flag set → `Aborted`. Never
  clears a flag belonging to a newer run.
- `conversations.pending_turn` holds a message that arrived mid-run; the
  `ensure` block consumes it and re-enqueues. Retry the acquire once after
  writing pending, to close the release race.
- Failure paths become records: placeholder results for orphaned
  `tool_use`s, a persisted apology, `conversations.state` actually set to
  `failed` (it is in `STATES` and has never been written).
- Prune empty assistant messages on run start — `content: []` replays as a
  400.

The token columns are what tell us how 8.5¢/turn splits between cached
prefix, fresh input, and output — and therefore whether C7's routing or
shorter answers is the real cost lever.

### C4 — Turns run in a job; SSE becomes a relay

- The controller persists the message and enqueues `Chat::CompletionJob`.
  No LLM work in the request cycle.
- `conversation_events` table; the job appends the event shapes
  `AgentLoop#emit` already produces, with text deltas coalesced so the table
  does not take a row per token.
- `GET /conversations/:id/stream` tails it and honours `Last-Event-ID`, so a
  reconnect mid-turn **resumes the narration** rather than waiting blind.
- `DELETE /conversations/:id/run` sets the abort flag; a stop button in the
  UI.

Trade-off: text streaming coarsens to ~150ms chunks. In exchange a turn
survives a proxy timeout, a deploy, and a closed laptop, and Puma threads
stop being held for a minute at a time. The inline `ActionController::Live`
turn is replaced outright rather than kept alongside.

### C5 — Prompts as code, plus the volatile block

`Chat::SystemPrompt` with ordered, individually snapshot-tested sections:
instructions → topology → **cache breakpoint** → a trailing volatile block
carrying the caller's profile snapshot, the time, and the page context the
client sent. A spec asserts nothing per-request sits above the breakpoint —
the property the live run proved by accident.

Payoffs: most turns stop spending a `get_profile` round-trip, and "what can
I eat here" from a restaurant page becomes one tool call instead of three.
`bin/prompt-tokens` prints the section sizes so one cannot silently double.

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
