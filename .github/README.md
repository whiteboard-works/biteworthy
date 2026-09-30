# `.github/`

Repository automation. Each file's purpose:

| File | Purpose |
|---|---|
| `workflows/ci-js.yml`     | Typecheck, lint, test + api-types codegen drift check for `apps/web`, `apps/mobile`, `packages/*`. Runs on every PR; a `changes` job skips the heavy work when no JS paths changed (skipped still satisfies required checks). |
| `workflows/ci-api.yml`    | RSpec + Brakeman + Rubocop (all blocking) for `apps/api`. Same every-PR + internal-skip structure. Postgres 16 service. |
| `workflows/ci-nightly.yml`| Nightly (09:00 UTC) full run of both suites against master regardless of paths; opens/updates a `ci-nightly`-labeled issue on failure. The backstop — auto-merged PRs don't trigger master-push CI (GITHUB_TOKEN events are suppressed). |
| `workflows/migration-guard.yml` | Fails any PR that edits/deletes a previously-shipped file under `apps/api/db/migrate/`. |
| `workflows/expo-align.yml`| Monthly `npx expo install --fix` + react-test-renderer sync; opens an alignment PR when drift exists. Owns Expo-managed versions (dependabot ignores them). |
| `workflows/codeql.yml`    | CodeQL scans for JS/TS and Ruby on every PR + weekly. |
| `workflows/pr-title.yml`  | Conventional-commit format check on every PR title. |
| `workflows/labeler.yml`   | Auto-applies `area:*` labels by changed paths. Config in `labeler.yml`. |
| `workflows/auto-merge.yml`| Enables squash auto-merge on every PR; branch protection's required checks decide when the merge actually happens. |
| `labeler.yml`             | Path → label mapping. |
| `dependabot.yml`          | Weekly grouped dep PRs (npm + bundler) + monthly actions bumps. |
| `CODEOWNERS`              | Review routing. |
| `PULL_REQUEST_TEMPLATE.md`| Standard PR description (Summary bullets on the why + a "How this could fail" bullet). |

## Standards

1. **PR titles** are conventional-commit-formatted; the squash-merge
   commit message inherits them. The `pr-title` workflow enforces this.
2. **Path filtering happens inside the workflows** (a `changes` job +
   job-level `if`), not at the trigger — so every PR reports every
   required check, while docs-only PRs still skip the heavy work.
   Don't move the filters back to the trigger: a required check that
   never reports blocks the PR forever.
3. **Concurrency groups** cancel in-progress runs when a new commit
   lands. The newest commit's CI is the only one that matters.
4. **Pinned major versions** (e.g. `@v6`) on every action — no
   floating `@latest`, no SHA-pinning churn.
5. **Required checks** for merge to master (enforced since
   2026-06-11): `typecheck · lint · test`, `rspec · brakeman ·
   rubocop`, `javascript-typescript`, `ruby`. Note these are check-run
   (job) names, not `workflow / job-id` strings. Managed in repo
   Settings → Branches (or `gh api .../branches/master/protection`).
6. **Auto-merge** is enabled on every non-draft PR (the label gate was
   dropped 2026-04-29). Branch protection still gates everything —
   failing CI blocks the merge; open a draft to hold a PR.
7. **Brakeman and Rubocop both block.** Rubocop inherits Rails' omakase
   style plus a generated `.rubocop_todo.yml` that freezes the pre-existing
   offences; new code must be clean, shrink the todo when the queue is quiet.

## Required labels (create once in repo settings)

- `area:api`, `area:web`, `area:mobile`, `area:packages`, `area:docs`,
  `area:ci`, `area:legacy` (auto-applied by `labeler.yml`)
- `claude-cd`, `auto-merge-ok` (manual; tagging only — neither gates auto-merge)
- `blocked`, `needs-review`, `wip` (manual; team conventions)

If a label doesn't exist when the labeler runs, it's auto-created with
a default color. No prep needed.
