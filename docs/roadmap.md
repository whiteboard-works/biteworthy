# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
live phases link to a `docs/plans/phase-N.md` subplan with the gory
details (shipped subplans are archived under `docs/plans/archive/`).

## Status

**Phases 0–8 + the legal-remediation arc have all shipped** (#112–#346).
The product is feature-complete: anyone-can-scan ingestion, the
real-world mobile scan loop, "most likely to enjoy" taste ranking, and
honest privacy/ToS + E1–E13 engineering are all on master. The full
per-PR history, each phase's demo, and the resolved follow-ups live in
[`status-archive/roadmap-phases-0-8.md`](status-archive/roadmap-phases-0-8.md);
the per-task acceptance criteria are in `docs/plans/archive/`.

Everything remaining is human-credential-gated launch work — see
**Next up** and `docs/launch-readiness.md`.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Launch gates** (human, not the loop): the L1–L5 legal gates (remove
`/privacy` + `/terms` DRAFT banners, lawyer sign-off, DMCA agent
registration) in `docs/plans/legal-remediation-followups.md`, alongside
the credential-gated wiring below. `docs/launch-readiness.md` is the
linear human path from "code complete" to launch.

1. **[BLOCKED] Phase 5.9-wiring — generate binary assets + screenshot routes + EAS submit** (followup to #180). Needs Apple Developer ($99/yr) + Google Play Console ($25 one-time) + lawyer signoff on `/privacy` + `/terms` + designed icon-source.svg.
2. **[BLOCKED] Phase 5.1.1-wiring — CI-driven `kamal deploy` on master push** (followup to #182). Needs first manual `kamal deploy` to prove the manual flow works before CI automation; that needs the Hetzner + Neon + GHCR provisioning per `docs/launch-readiness.md` step 1.

**Admin backoffice workstream — SHIPPED 2026-07-30** (#467–#481,
session-driven): all admin capability lives in `apps/web` `/admin`
(dashboard, ingestion moderation, reviews/suggestions, taxonomy,
restaurants/items/users), backed by the `Api::V1::Admin` JSON
namespace (`require_admin!` → 404; `users.is_admin` via
`admin:grant/sync` rake tasks). Avo, the ERB `/admin/dashboard`, and
the `ADMIN_USERNAME`/`ADMIN_PASSWORD` basic-auth gate are deleted.
Deferred to v2: taxonomy merge + subtree rename, join-level
ingredient/tag editing, debounced admin search.

**Upstream-editing workstream** (started 2026-07-31, session-driven):
fix data as far upstream as possible — staged items fully editable
before accept, and admins able to edit anything at a restaurant (the
CRUD parity Avo used to provide). Sequence:

- [x] E1 — API: permit `prices_payload` in staged-item edits; real payload row schemas
- [x] E2 — web: verify-flow edit panel (name, description, chips, prices); admin run review inherits
- [x] E3 — API: admin item deep-edit (variants, modifiers, ingredient/tag join sync, section move)
- [ ] E4 — web: admin item deep-edit panel
- [x] E5 — API: admin menus, sections, addresses, hours
- [ ] E6 — web: admin structure + place editors

Invariants: join `confidence` never directly editable (admin chip edits
write `confirmed`/`human`, removals row-by-row so the denormalized
arrays stay honest); matched re-scan cards stay append-only.

Other than that workstream, **no remaining loop-shippable work.** Every
loop-shippable launch piece is on master; the remaining queue is
entirely human-credential-gated.

## Open follow-ups

Loop-surfaced tasks that don't belong to a shipped phase. Humans triage
these into the launch path or a future phase. (Resolved follow-ups are
in the [roadmap history](status-archive/roadmap-phases-0-8.md).)

- **`/login?next=` is an open redirect** — `login/page.tsx` replaces to
  whatever `?next=` holds without validating it starts with `/`, so
  `/login?next=https://evil.com` bounces a successful login off-site.
  Pre-dates the admin workstream (the suggestions queue minted these
  links first) but W1 added another producer. Fix: `startsWith('/')`
  guard (reject `//`) before `router.replace`.

- **Onboarding-chip flake recurred (3rd occurrence)** — the test fixed
  in #199 ("renders a chip per preset once the fetch resolves") timed
  out again on #304's CI runner (suite took 16.5s; 5s per-test cap).
  The findByLabelText fix helped locally but slow CI runners still trip
  it. Candidate fixes: bump that test's timeout to 15s, or
  jest.setTimeout for the file. One-line change; fold into the next
  mobile PR.
- **Phase 6.5/6.6 codex P2 followups (web+mobile verify UX)** — from
  #304's review, all reasonable, none blocking: (1) logged-out users
  hit the create step before any 401 redirect — picker should redirect
  like upload does; (2) no edit-before-accept path in the web verify
  list (API supports `edited`; mobile verify has it); (3) "did you mean"
  cards offer other users' DRAFTS as reusable targets, which then 403 at
  scan time — filter candidates to published-or-own; (4) web verify
  polling stops permanently on one transient fetch failure — retry with
  backoff. Also applies partly to mobile picker (3).
- **Ingestion + restaurant endpoints lack rswag specs** (noted while
  shipping 6.1/6.2). `POST /ingestion_runs`, `PATCH .../items/:id`,
  `POST /restaurants` aren't in `docs/openapi.json`, so api-types stays
  hand-written for them. One PR could rswag the lot + re-run codegen.
- **Auto-merge race lost a follow-on commit (#150, #172)** — twice a
  second commit was added before CI finished and auto-merge had already
  enabled on the first sha and squashed without the second diff. Either
  push everything in one go, or gate auto-merge on a manual "ready"
  label after final push.

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
</content>
