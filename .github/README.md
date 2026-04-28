# `.github/`

Repository automation. Each file's purpose:

| File | Purpose |
|---|---|
| `workflows/ci-js.yml`     | Typecheck, lint, test for `apps/web`, `apps/mobile`, `packages/*`. Path-filtered. |
| `workflows/ci-api.yml`    | RSpec + Brakeman + Rubocop for `apps/api`. Path-filtered. Postgres 16 service. |
| `workflows/codeql.yml`    | Weekly CodeQL scans for JS/TS and Ruby. |
| `workflows/pr-title.yml`  | Conventional-commit format check on every PR title. |
| `workflows/labeler.yml`   | Auto-applies `area:*` labels by changed paths. Config in `labeler.yml`. |
| `workflows/auto-merge.yml`| Enables squash auto-merge for PRs with `claude-cd` + `auto-merge-ok`, or any PR authored by `dependabot[bot]`. |
| `labeler.yml`             | Path → label mapping. |
| `dependabot.yml`          | Weekly grouped dep PRs (npm + bundler) + monthly actions bumps. |
| `CODEOWNERS`              | Review routing. |
| `PULL_REQUEST_TEMPLATE.md`| Standard PR description (Why / What / Test plan / Notes). |

## Standards

1. **PR titles** are conventional-commit-formatted; the squash-merge
   commit message inherits them. The `pr-title` workflow enforces this.
2. **Path filters** mean a docs-only PR doesn't run RSpec, and an
   API-only PR doesn't run JS checks. Faster, cheaper, less noise.
3. **Concurrency groups** cancel in-progress runs when a new commit
   lands. The newest commit's CI is the only one that matters.
4. **Pinned major versions** (`@v4`, `@v5`) on every action — no
   floating `@latest`, no SHA-pinning churn.
5. **Required checks** for merge to master: `CI · JS / check`,
   `CI · API / rspec`, `CodeQL / javascript-typescript`,
   `CodeQL / ruby`. Configure in repo Settings → Branches.
6. **Auto-merge** is opt-in per PR via labels (`auto-merge-ok` +
   `claude-cd`) and is automatic for `dependabot[bot]` PRs. Branch
   protection still gates everything — failing CI blocks the merge.
7. **`continue-on-error: true`** on Brakeman + Rubocop until the
   codebase grows to where they're meaningful. Re-tighten in Phase 1.

## Required labels (create once in repo settings)

- `area:api`, `area:web`, `area:mobile`, `area:packages`, `area:docs`,
  `area:ci`, `area:legacy` (auto-applied by `labeler.yml`)
- `claude-cd` (manual; marks loop-authored PRs)
- `auto-merge-ok` (manual; opts a PR into auto-merge)
- `blocked`, `needs-review`, `wip` (manual; team conventions)

If a label doesn't exist when the labeler runs, it's auto-created with
a default color. No prep needed.
