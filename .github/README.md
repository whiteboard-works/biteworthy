# `.github/`

Repository automation. What each file does:

| File                            | Purpose                                                                                                                                                                                                                                                                            |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `workflows/ci-js.yml`           | Typecheck, lint, test, and the api-types codegen drift check for `apps/web`, `apps/mobile`, `packages/*`. Runs on every PR; a `changes` job skips the heavy work when no JS path changed (a skipped job still satisfies the required check).                                       |
| `workflows/ci-api.yml`          | RSpec, Brakeman, and Rubocop for `apps/api`, all blocking. Same every-PR and skip-inside structure, with Postgres 16, ImageMagick, and Ghostscript on the runner.                                                                                                                  |
| `workflows/deploy-api.yml`      | Runs `kamal deploy` on a merge to `master` touching `apps/api/**` or the workflow itself, and on manual dispatch. Logs into GHCR with its own `GITHUB_TOKEN`; needs the `KAMAL_SECRETS_B64`, `SSH_PRIVATE_KEY`, and `SSH_KNOWN_HOSTS` secrets. The header comment is the run book. |
| `workflows/ci-nightly.yml`      | Nightly (09:00 UTC) full run of both suites against `master` regardless of paths; opens or updates a `ci-nightly` issue on failure. The backstop, because the PR workflows are path-filtered and a docs-only merge never exercises the suites.                                     |
| `workflows/migration-guard.yml` | Fails any PR that edits or deletes a previously shipped file under `apps/api/db/migrate/`.                                                                                                                                                                                         |
| `workflows/expo-align.yml`      | Monthly `npx expo install --fix` and react-test-renderer sync; opens an alignment PR when there is drift. Owns the Expo-managed versions (Dependabot ignores them).                                                                                                                |
| `workflows/codeql.yml`          | CodeQL for JS/TS and Ruby on every PR and weekly.                                                                                                                                                                                                                                  |
| `workflows/pr-title.yml`        | Conventional-commit check on every PR title.                                                                                                                                                                                                                                       |
| `workflows/labeler.yml`         | Applies `area:*` labels by changed paths. Config in `labeler.yml`.                                                                                                                                                                                                                 |
| `workflows/auto-merge.yml`      | Enables squash auto-merge on every non-draft PR, using `AUTOMERGE_TOKEN` so the resulting merge commit triggers `master` workflows (a `GITHUB_TOKEN` merge would start none, and the API would never deploy). Branch protection decides when the merge happens.                    |
| `labeler.yml`                   | Path to label mapping.                                                                                                                                                                                                                                                             |
| `dependabot.yml`                | Weekly grouped dependency PRs (npm and Bundler) plus monthly action bumps.                                                                                                                                                                                                         |
| `CODEOWNERS`                    | Review routing.                                                                                                                                                                                                                                                                    |
| `PULL_REQUEST_TEMPLATE.md`      | The PR body shape: Summary bullets on the why, plus one "How this could fail" bullet.                                                                                                                                                                                              |

## Standards

1. **PR titles** are conventional commits; the squash commit inherits them, and `pr-title` enforces it.
2. **Path filtering happens inside the workflows** (a `changes` job plus job-level `if`), not at the trigger, so every PR reports every required check while docs-only PRs skip the heavy work. A required check that never reports blocks the PR forever, so do not move the filters back to the trigger.
3. **Concurrency groups** cancel in-progress CI when a new commit lands. The deploy is the exception: it serializes and never cancels mid-flight.
4. **Pinned major versions** on every action, no floating `@latest` and no SHA churn.
5. **Required checks** for `master` (since 2026-06-11): `typecheck · lint · test`, `rspec · brakeman · rubocop`, `javascript-typescript`, `ruby`. These are check-run names, not `workflow / job-id` strings. Managed in Settings → Branches.
6. **Auto-merge is on for every non-draft PR.** The label gate was dropped 2026-04-29. CI green is the whole gate, so review before opening a PR ready, and open a draft to hold one.
7. **Brakeman and Rubocop both block.** Rubocop inherits Rails' omakase style plus `.rubocop_todo.yml`, which freezes the old offences; new code must be clean.

## Labels

`area:api`, `area:web`, `area:mobile`, `area:packages`, `area:docs`,
`area:ci`, `area:legacy` are applied by the labeler and created on first use.
`claude-cd` and `auto-merge-ok` are tagging only; neither gates anything.
