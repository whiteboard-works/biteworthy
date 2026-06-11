# Automations TODO

Longterm-development automation work, ordered by priority. Motivated by
the June 2026 incident (tick #128 in `docs/status.md`): ~45 dependabot
PRs auto-merged on red because required checks weren't enforced after
the org move, and master was broken for ~3 weeks unnoticed.

Status legend: `[ ]` queued · `[~]` in progress · `[x]` done · `[B]` blocked (needs human)

## P0 — merge safety net

1. [~] **CI workflows report on every PR** so required checks can be
   enforced. Today both workflows are path-filtered at the trigger, so
   a docs-only PR never reports `CI · JS / check` — making it a
   required check would block those PRs forever. Move the path filter
   inside the workflow (change-detection job + job-level `if`; GitHub
   treats skipped required jobs as satisfied). Also: make Brakeman
   blocking if it's currently clean, and add a failure hint to the
   codegen drift check.
2. [~] **Enforce required status checks on `master` branch protection**
   (`CI · JS / check`, `CI · API / rspec` — exact contexts verified at
   apply time). Apply via `gh api` after item 1 merges; if the token
   lacks admin, falls back to a human task (Settings → Branches).
3. [~] **Nightly full-suite CI on master** (`schedule:` cron) running
   both the JS and API suites regardless of paths, opening/updating a
   pinned issue on failure. Closes the "docs merge never runs rspec,
   master rots invisibly" gap.
4. [~] **Migration guard** — CI check that fails any PR which modifies
   or deletes a previously-shipped file under `apps/api/db/migrate/`
   (new migrations are fine). Makes the playbook rule mechanical.

## P1 — dependency hygiene

5. [~] **Dependabot ignore rules for Expo-managed packages**
   (`expo*`, `react-native*`, `jest-expo`, `jest`, `@types/jest`,
   `react-test-renderer`) — these are coupled to the Expo SDK and must
   move together, not one-at-a-time. Note: `react`/`react-dom` are
   deliberately NOT ignored (web needs them); accepted residual risk,
   the nightly run + required checks now catch a bad bump.
6. [~] **Monthly Expo SDK alignment workflow** — scheduled job that
   runs `npx expo install --fix`, reinstalls, runs the suite, and opens
   a PR with the aligned versions. The deliberate replacement for
   dependabot's per-package Expo bumps.

## P2 — deploy + ops (blocked on launch provisioning)

7. [B] **CI-driven `kamal deploy` on master push + post-deploy
   `kamal smoke`** — already queued as Phase 5.1.1-wiring; needs the
   first manual deploy (Hetzner + Neon + GHCR provisioning,
   `docs/launch-readiness.md` step 1).
8. [B] **Uptime probe + daily production smoke cron** (`/up` poll +
   `biteworthy:production:smoke` via `kamal app exec`) — needs a live
   deploy to point at.

## P3 — agent loop

9. [B] **Restart the `/loop 30m` delivery loop** (or convert to a
   scheduled cloud agent) once the queue has unblocked work — human
   decision on cadence/cost.
10. [ ] **Weekly reconcile tick** — even while the queue is blocked,
    compare merged PRs against `docs/roadmap.md` + `docs/status.md`,
    sync drift, and flag anomalies (e.g. merges with failing CI).
    Can be a scheduled agent; design after items 1–6 settle.
