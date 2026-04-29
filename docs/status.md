# Delivery status log

The autonomous loop's running log. Newest entries on top. One line per
tick or significant event. Format:

```
YYYY-MM-DD HH:MM (UTC) — <summary>
```

The point is breadcrumbs: a tick interrupted at minute 28 should leave
enough here for the next tick (or a human dropping in) to resume
without spelunking GitHub.

---

2026-04-28 22:35 — tick #2. PR #128 CI red: 17/17 specs failing 500.
Root cause: api_only Rails strips session middleware → OmniAuth's
strategy raises NoSessionError on every request (including /up).
Diagnosed by starting postgres@16 locally, reproducing with
`bin/rspec`, reading log/test.log. Pushed three fixes in one
commit (06fc7c9): (a) reinjected ActionDispatch::Cookies + Session
in application.rb, (b) skipped Devise's `/api/v1/auth/auth/:provider`
double-prefix routes — set OmniAuth.config.path_prefix +
custom clean routes for /api/v1/auth/:provider per phase-1.md spec,
(c) `||=` was a no-op against the `default: ""` email column → use
`if blank?`. Local rspec: 17 examples, 0 failures. Waiting on CI
re-run to confirm green; next tick checks merge state.

2026-04-28 21:55 — opened #128 phase-1.2-omniauth (+362/-3); 5 specs
across google + apple (new/returning/failure). Created `claude-cd` +
`auto-merge-ok` labels on the repo (referenced by playbook + auto-
merge.yml but never created). Requested `@codex review`. CI checks
in flight: ci-api (rspec/brakeman/rubocop), CodeQL (js + ruby),
labeler, title-lint. Waiting for CI; next 30-min tick checks state.

2026-04-28 21:30 — loop tick (resumed). Reconciled stale log: PR #124
(phase-1.1) merged at 2026-04-29 01:16 UTC; `Done` already ticked in
roadmap. Picked up Phase 1.2 — opened branch
`claude/phase-1.2-omniauth`. Implemented: `:omniauthable` on User,
`User.from_omniauth`, `OmniauthCallbacksController` (google_oauth2 +
apple + failure), routes wired, `config/initializers/omniauth.rb`
(allow GET request method, on_failure → controller), `.env.example`
documenting GOOGLE_/APPLE_/DEVISE_JWT_ env vars, request specs in
test_mode covering google new/returning/failure + apple
new/returning. Local rspec deferred (no postgres service running on
this dev box); CI's postgres container will exercise. Next: push +
open PR + request `@codex review`.

2026-04-28 20:05 — loop tick #1. PR #124 (phase-1.1) open, CI pending
on all 5 checks after title-fix push, `area:api` label applied. Per
playbook: wait for CI, no action. Subscribed to PR activity; webhook
events will trigger the next handler. Cron primitive (CronCreate) not
loaded in this session — relying on webhooks + user pings for
heartbeat instead of a true 30-min cadence.

2026-04-28 19:55 — Phase 1.1 complete locally; opening PR. 12 request
specs green covering signup happy/dup/invalid, login happy/wrong-pw/
ghost, logout rotates jti + invalidates old token, refresh rotates jti
+ invalidates old token + rejects no-token. Includes a stub
`Api::V1::ProfilesController#show` so the auth-gating specs have a
real protected route — Phase 1.3 owns its full GET/PATCH semantics.

2026-04-28 09:30 — PR #112 (master CI rebuild + GitHub Actions
modernization) merged. CI now green: 6 workflows, dependabot,
labeler, auto-merge gate, conventional-commit PR title check,
CodeQL, code owners.

2026-04-28 09:10 — PR #111 (delivery framework) merged. Playbook +
status log + phase subplan + restructured roadmap on master.

2026-04-28 09:00 — Phase 0 merged (PR #110). Some master CI red —
added to Next-up as a subtask. Framework PR (`claude/delivery-framework`)
opening shortly with playbook v2, status log, phase-1 subplan, roadmap
restructure.
