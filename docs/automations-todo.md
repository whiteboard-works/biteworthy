# Automations TODO

Longterm-development automation work, ordered by priority. Motivated by
the June 2026 incident (tick #128 in `docs/status.md`): ~45 dependabot
PRs auto-merged on red because required checks weren't enforced after
the org move, and master was broken for ~3 weeks unnoticed.

Status legend: `[ ]` queued · `[~]` in progress · `[x]` done · `[B]` blocked (needs human)

> **P0 + P1 are complete** (the June 2026 merge-safety remediation, #278–#283 + branch protection; kept below for reference). The only open work is **P2** (blocked on launch provisioning) and **P3** (the agent loop). Skip to those.

## P0 — merge safety net

1. [x] **CI workflows report on every PR** so required checks can be
   enforced — done in #280. Path filters moved from the `pull_request`
   trigger into a `changes` job (`dorny/paths-filter`, bumped to v4 by
   #282) gating the heavy job; skipped jobs satisfy required checks.
   Brakeman was clean → now blocking; Rubocop stays informational.
   Codegen drift check now prints exact fix commands on failure.
2. [x] **Enforce required status checks on `master` branch protection**
   — applied 2026-06-11 via `gh api` (the token had admin). Required
   contexts: `typecheck · lint · test`, `rspec · brakeman · rubocop`,
   `javascript-typescript`, `ruby` (check-run names, not the
   "workflow / job-id" form). `strict` is off; admins not enforced.
   Verified working: red dependabot PRs are now blocked from merging.
3. [x] **Nightly full-suite CI on master** — done in #278
   (`.github/workflows/ci-nightly.yml`, 09:00 UTC + workflow_dispatch;
   on failure opens/updates an issue labeled `ci-nightly` mentioning
   @shadoath). Extra reason it matters, discovered during rollout:
   master-push CI runs are SUPPRESSED for auto-merged PRs (the merge
   is attributed to GITHUB_TOKEN, whose events don't trigger
   workflows) — the nightly is currently the only thing that runs CI
   against master itself.
4. [x] **Migration guard** — done in #281
   (`.github/workflows/migration-guard.yml`): fails any PR that
   modifies/deletes/renames an existing file under
   `apps/api/db/migrate/`; additions pass.

## P1 — dependency hygiene

5. [x] **Dependabot ignore rules for Expo-managed packages** — done in
   #279 (12 ignore patterns; the `expo` group removed). Note:
   `react`/`react-dom` are deliberately NOT ignored (web needs them);
   accepted residual risk — required checks + the renderer-sync step in
   the align workflow now catch a bad bump. Painfully validated: #276
   (an expo-group bump) merged minutes BEFORE the ignores landed,
   re-broke mobile, and was cleaned up by #292.
6. [x] **Monthly Expo SDK alignment workflow** — done in #283
   (`.github/workflows/expo-align.yml`), patched in #292 after its
   first dispatched run correctly caught — but couldn't fix — the
   react-test-renderer/react version mismatch (the workflow now syncs
   the renderer pin after `expo install --fix`). Known limitation:
   the PRs it opens via GITHUB_TOKEN don't trigger CI; close/reopen
   them to get checks, which are now required to merge.

## P2 — deploy + ops (blocked on launch provisioning)

7. [~] **CI-driven `kamal deploy` on master push + post-deploy
   `kamal smoke`** — the deploy half is **done**: `deploy-api.yml` ships
   every master push touching `apps/api/**`, including auto-merged PRs
   (which needs `AUTOMERGE_TOKEN`; it exists). The smoke half is **not** —
   `deploy-api.yml` ends at `kamal deploy` and secret cleanup, so a deploy
   that boots a broken release is not caught by anything here.
8. [ ] **Uptime probe + daily production smoke cron** (`/up` poll +
   `biteworthy:production:smoke` via `kamal app exec --roles web`) —
   unblocked: the API has been live since 2026-07 and deploys itself. This
   and #7's smoke half are the same gap seen from two directions, and
   nothing currently notices a bad release.

## P3 — agent loop

9. [B] **Restart the `/loop 30m` delivery loop** (or convert to a
   scheduled cloud agent) once the queue has unblocked work — human
   decision on cadence/cost.
10. [ ] **Weekly reconcile tick** — even while the queue is blocked,
    compare merged PRs against `docs/roadmap.md` + `docs/status.md`,
    sync drift, and flag anomalies (e.g. merges with failing CI).
    Can be a scheduled agent; design after items 1–6 settle.
