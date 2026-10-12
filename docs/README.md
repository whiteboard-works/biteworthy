# `docs/`

The project's memory. Three kinds of file live here, and the kind tells you
how much to trust a sentence:

- **Living** docs are kept current in the same PR as the work they describe. If one disagrees with the code, the doc is the bug.
- **Reference** docs record a decision or a stable fact. They are not updated when the world moves; a superseding note at the top says where to look instead.
- **Archive** is history, read-only. Nothing in it should be used to plan work.

If you are new, read [`local-dev.md`](local-dev.md) to run the project and
[`schema.md`](schema.md) for the data model, then whichever living doc covers
the area you are touching. The rules for agents are in the repo root
[`AGENTS.md`](../AGENTS.md), not here.

## Living

| Doc                                            | Come here for                                                                                                                                                         |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`roadmap.md`](roadmap.md)                     | What is in progress and what is next. Each live arc links to its plan under `plans/`.                                                                                 |
| [`status.md`](status.md)                       | The day-by-day log, newest first: what shipped, what was decided, what broke and why. Entries older than September 2026 are in `status-archive/`.                     |
| [`local-dev.md`](local-dev.md)                 | The run book: containerized or native, tests, the usual snags.                                                                                                        |
| [`schema.md`](schema.md)                       | The data model in 60 seconds: the ~30 tables, the denormalized id arrays, the confidence and source columns the filter depends on.                                    |
| [`mcp.md`](mcp.md)                             | The tool layer: how a tool is declared, gated, and offered to the chat and to MCP clients, and the `/mcp` endpoint's OAuth. Read before adding a capability.          |
| [`ingestion.md`](ingestion.md)                 | How a menu photo, PDF, or link becomes staged dishes: the model calls, the taxonomy cache, confidence, the review step.                                               |
| [`analytics.md`](analytics.md)                 | The funnel-event contract behind `packages/analytics`. Renaming an event breaks a dashboard.                                                                          |
| [`launch-readiness.md`](launch-readiness.md)   | The human-action checklist for provisioning and launch. The checklist in the back half is current; the inventory in the front half is a 2026-04 snapshot and says so. |
| [`delivery-playbook.md`](delivery-playbook.md) | The procedure the autonomous delivery loop follows, including the auto-merge policy.                                                                                  |
| [`automations-todo.md`](automations-todo.md)   | Automation work by priority; what is left is launch-blocked or belongs to the agent loop.                                                                             |
| [`openapi.json`](openapi.json)                 | Generated from the API's rswag specs by `bin/openapi-export`; feeds `packages/api-types`. Never edit by hand.                                                         |

### Live plans (`plans/`)

Per-arc acceptance criteria for work in flight. A plan whose every box is
ticked moves to `plans/archive/`.

| Plan                                                                     | Scope                                                                                          | State                                                                                   |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| [`chat-engine.md`](plans/chat-engine.md)                                 | The chat loop as a system: parking, grounding review, compaction, cache, the clock, questions. | Phases C1–C9 shipped; the decisions table (C-D1…) and open questions are the live part. |
| [`chat-results-pane.md`](plans/chat-results-pane.md)                     | The results pane beside the transcript.                                                        | P1 shipped; P2 and P3 open.                                                             |
| [`mcp-pivot.md`](plans/mcp-pivot.md)                                     | The tool layer becomes the product surface (M1–M8).                                            | M7 open.                                                                                |
| [`profile-location.md`](plans/profile-location.md)                       | Home city and device location: "what is nearby".                                               | Web shipped; mobile and results-pane distance open.                                     |
| [`legal-remediation-followups.md`](plans/legal-remediation-followups.md) | Code follow-ups after the E1–E13 legal work, plus the L1–L5 attorney and ops gates.            | L1–L5 open.                                                                             |
| [`chat-privacy-l1-brief.md`](plans/chat-privacy-l1-brief.md)             | The brief for the L1 attorney review of what the chat sends to Anthropic.                      | Awaiting the review.                                                                    |
| [`taste-quiz.md`](plans/taste-quiz.md)                                   | A taste-quiz onboarding.                                                                       | Draft; no code yet.                                                                     |
| [`filter-loop.md`](plans/filter-loop.md)                                 | The first signed-in filter path, end to end.                                                   | Every box ticked; archive candidate.                                                    |
| [`six-month-plan.md`](plans/six-month-plan.md)                           | The strategy reversed into `[MANUAL]` and `[CODE]` tasks with decision gates.                  | Partly stale; being reconciled with `strategy-2026-h2.md` and `launch-plan.md`.         |
| [`ux-exploration-2026-08-15.md`](plans/ux-exploration-2026-08-15.md)     | Findings from walking the live product as a user.                                              | All but one item shipped 2026-08-15; archive candidate.                                 |
| [`verify-flow-redesign.md`](plans/verify-flow-redesign.md)               | Instant dishes plus background enrichment for the swipe-verify flow.                           | Superseded: ingestion moved into the chat on 2026-08-07. Archive candidate.             |

## Reference

| Doc                                          | Come here for                                                                                                                                                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`vision.md`](vision.md)                     | The product thesis, the moat, and the arc. Why this exists.                                                                                                                                                              |
| [`strategy-2026-h2.md`](strategy-2026-h2.md) | The mid-2026 diagnosis, positioning, and six-month plan. Its checkboxes lag the log.                                                                                                                                     |
| [`launch-plan.md`](launch-plan.md)           | The two-track launch plan: manual provisioning, and the code that lowers the gate for a first-time visitor. Partly shipped; partly stale.                                                                                |
| [`adr/`](adr/)                               | Why each big pick is what it is: stack (0001), email (0003), blobs (0004), web hosting (0005), analytics (0006), API hosting (0007), error reports (0008), observability (0009). 0002 is superseded by 0007 and says so. |
| [`outreach/`](outreach/)                     | Press pitch templates for the Durango outlets and the launch-day posts.                                                                                                                                                  |
| [`legal/`](legal/)                           | A draft one-way NDA template. Not legal advice.                                                                                                                                                                          |
| [`seeds/`](seeds/)                           | The shape of the Durango seed CSV (`durango.csv.example`); the real file is not committed.                                                                                                                               |

## Archive

| Path                                             | What it is                                                                                                                                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`plans/archive/`](plans/archive/)               | Acceptance criteria for phases 1–8, dish photos, and the legal remediation, with the PR ranges that shipped them. Its README has the rule.                                                 |
| [`status-archive/`](status-archive/)             | Older log entries by date range, and the phase-by-phase roadmap history (`roadmap-phases-0-8.md`).                                                                                         |
| [`archive/bw2-planning/`](archive/bw2-planning/) | The 2026-06 planning docs for moving off the 2020 app. They describe a Rails + Hotwire + Elasticsearch stack the project did not keep; the API-plus-clients stack won. Nothing links here. |
