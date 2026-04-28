# Delivery playbook

The recipe followed by the autonomous delivery loop (a `/loop 30m` task
running every 30 minutes) and any human picking up where it left off.

This document is the source of truth. The loop reads from it; humans read
from it. If the loop's behavior diverges from this file, the file wins.

## Operating principles

1. **PR per task.** One PR per item in `docs/roadmap.md`'s "Next up"
   queue. No artificial size cap — a thorough Phase 1.1 (controllers +
   routes + specs + factories + docs) lives in one PR. Don't split a
   coherent task across two PRs just to be small. *Don't* bundle
   unrelated work to be big.
2. **Tests are part of the task.** A PR without tests for the new
   behavior is incomplete. RSpec for the API, Vitest for filter-engine,
   Vitest/RTL for web, Jest/RTL for mobile.
3. **Review cycles are part of the task.** Every PR opened by the loop
   automatically requests `@codex review` and (when the loop is
   confident in the change) at least one self-review pass before
   marking ready-for-merge.
4. **CI must pass.** Never request human review on red. Never
   auto-merge on red.
5. **Trust review.** Auto-merge runs only after CI is green AND no
   unresolved review threads AND `@shadoath` (the project owner) has
   either explicitly approved or labeled the PR `auto-merge-ok`.
6. **Plan-first updates.** Before starting work, the loop syncs
   `docs/roadmap.md`'s "Next up" queue. Before merging, it ticks the
   completed item. Mid-task progress goes in `docs/status.md` (see
   §Status log).
7. **Ping when stuck.** Three failed CI runs in a row, an unaddressed
   human review comment that needs a judgement call, or any
   `[BLOCKED]` item promoted to next pauses the loop and pings
   `@shadoath` via a PR comment.
8. **Honest scope.** Don't pull next-phase work into a current-phase
   PR. Don't refactor adjacent code while fixing a bug. Don't add
   features the roadmap didn't ask for.
9. **Subplans for depth.** Each phase has a `docs/plans/phase-N.md`
   that decomposes the phase into ordered tasks, gotchas, and
   acceptance criteria. The roadmap's "Next up" links into the
   relevant subplan.

## The loop

Each tick runs this sequence top-to-bottom and stops at the first
applicable branch.

### 1. Read state

- `git fetch origin`
- Read `docs/status.md` to see what the previous tick left off doing.
- Identify the latest open PR authored by the loop (label
  `claude-cd` or branch matching `claude/*`).
- Pull its check status, review threads, merge state, and any new
  comments since last tick.

### 2. Branch on PR state

| State | Action |
|---|---|
| PR open, CI green, approved (or `auto-merge-ok` labeled), no unresolved threads | **Squash-merge**, then continue to step 3. |
| PR open, CI green, awaiting `@codex review` | Wait. Log "awaiting codex" in `docs/status.md`. |
| PR open, CI green, has unresolved review threads | Read each thread. If small + clear, address and push. If ambiguous or architectural, post a question on the thread tagging `@shadoath` and pause. |
| PR open, CI red | Fetch the failing logs. If the cause is known and the fix is small, push it to the same branch. If unknown after one diagnosis attempt, post a status comment summarizing the failure, ping `@shadoath`, and pause. |
| PR open, CI pending | Do nothing. Log "waiting for CI." |
| PR open, conflicts with master | Rebase onto master. If conflicts are mechanical, resolve and force-push. If non-trivial, ping and pause. |
| No PR open, branch has commits | Open the PR, request codex review, do a self-review pass, then continue to step 3. |
| No PR open, working tree clean | Continue to step 3. |

### 3. Update the plan

- Tick the merged item in `docs/roadmap.md`.
- Append a status entry to `docs/status.md` (one line per tick:
  timestamp, what changed, what's next).
- If the merged work surfaced followup work, add it to the
  roadmap's "Discovered" section. **Don't silently expand the
  Next-up queue** — discovered items get a human review before
  they're picked up.

### 4. Pick the next item

- Read `docs/roadmap.md` "Next up" queue.
- Take the topmost unblocked item.
- Open the relevant `docs/plans/phase-N.md` to confirm scope.
- Create a branch: `claude/<phase-slug>` from origin/master.

### 5. Do the work

- Implement the item per its subplan.
- Run local checks before pushing:
  - `pnpm typecheck`, `pnpm lint`, `pnpm test` (the relevant subset)
  - `bundle exec rspec` (the relevant subset)
- Commit with a conventional message (`feat(api): ...`,
  `fix(web): ...`, `docs: ...`, `chore(ci): ...`).
- Push the branch.

### 6. Open the PR

- Title: `<scope>: <imperative summary>` (matches the roadmap
  item).
- Body sections: **Why** (linked roadmap item), **What** (bullet
  diff summary), **Test plan** (checklist), **Notes** (anything
  surprising).
- Labels: `claude-cd`, plus `auto-merge-ok` if the PR is small +
  mechanical (lockfile bumps, type regen, no behavior change).
- Request `@codex review` immediately.
- Subscribe to PR activity for webhook events.
- Append to `docs/status.md`.

### 7. End the tick

- The next tick (or webhook event) picks up state.

## Status log

`docs/status.md` is the loop's running log. One line per tick or
event, prepended (newest first). Format:

```
2026-04-29 14:32 — opened #123 phase-1.1-devise-jwt-login (+512/-3); requested codex
2026-04-29 14:31 — merged #122 delivery-framework; queue: phase-1.1
```

The log lets a human (or the next tick) reconstruct what happened
without scrolling GitHub. It's also where the loop posts mid-task
progress so a tick interrupted at the 28-minute mark leaves enough
breadcrumbs for the next tick to resume.

## Auto-merge policy

Auto-merge is enabled per-PR, never globally. The loop only enables
it when **all** of the following are true:

- The PR is in the `claude-cd` series.
- The PR description has a populated **Test plan** checklist.
- CI is green.
- `@codex review` has no unaddressed comments.
- Either `@shadoath` has approved OR the PR has the
  `auto-merge-ok` label.
- No file under `apps/api/db/migrate/` was edited destructively (a
  new migration is fine; editing a previously-shipped migration is
  not).
- No file under `_legacy/` was modified.

The loop never bypasses CI, never force-pushes to master, never
deletes branches it didn't create.

## Stop conditions (ping `@shadoath`)

The loop pauses (no action, posts status, pings) when:

- Same CI failure 3 ticks in a row → human intervention requested.
- An open review thread contains `?` or starts with "should we" or
  "why" → treated as a question that needs a human answer.
- A roadmap item carries a `[BLOCKED]` prefix → skip; do not start.
- The next item requires secrets the loop doesn't have (Apple
  signing key, Anthropic API key in CI, etc.) → skip with a
  status comment.
- Diff size for a single PR exceeds 2,000 lines without a clear
  reason → pause and propose splitting.

How to ping: post a top-level PR comment that starts
`@shadoath` followed by a one-paragraph status. GitHub's default
notifications email this to the owner.

## Cadence

- **Default**: 30 minutes per tick.
- **Burst**: subscribed PR webhook events (CI completed, review
  submitted, comment posted) trigger an immediate handler outside
  the cadence.
- **Quiet hours**: none — the loop's state is small enough that a
  Sunday-morning tick is harmless.

## Cron prompt

The loop is started with:

```
/loop 30m Run one tick of the BiteWorthy delivery loop. Read
docs/delivery-playbook.md (procedure), docs/roadmap.md (queue),
and docs/status.md (last-tick state). State your read of the world
in one paragraph before acting. Stop when stuck per the playbook.
```

The procedure lives in this file so it can evolve via PR like any
other code. If the playbook changes mid-loop, the next tick picks
up the new version automatically.
