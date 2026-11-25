# Working rules

How agents work in this repo. They apply to every task unless explicitly overridden. Bias: caution over speed on non-trivial work; use judgment on trivial tasks. The always-loaded rules are in the root `AGENTS.md`.

## 1. Think, checkpoint, fail loud

State assumptions explicitly. If uncertain, ask rather than guess. Stop when confused and name what's unclear. After each significant step, summarize what was done, what's verified, what's left. "Completed" is wrong if anything was skipped silently; "tests pass" is wrong if any were skipped. Default to surfacing uncertainty, not hiding it.

## 2. Simplicity first

Minimum code that solves the problem. Nothing speculative. No features beyond what was asked. No abstractions for single-use code. Test: would a senior engineer say this is overcomplicated? If yes, simplify.

## 3. Surgical changes

Touch only what you must. Clean up only your own mess. Don't "improve" adjacent code, comments, or formatting. Don't refactor what isn't broken.

## 4. Goal-driven execution

Define success criteria. Loop until verified. Strong success criteria let you loop independently.

## 5. Use the model only for judgment calls

Use the LLM for classification, drafting, summarization, extraction. Do not use it for routing, retries, or deterministic transforms. If code can answer, code answers. This matters most in the ingestion pipeline (`docs/ingestion.md`).

## 6. Read before you write

Before adding code, read exports, immediate callers, shared utilities. "Looks orthogonal" is dangerous. If unsure why code is structured a way, ask.

## 7. Tests verify intent, not just behavior

Tests must encode why behavior matters, not just what it does. A test that can't fail when business logic changes is wrong.

## 8. Surface conflicts, don't average them

If two patterns contradict, pick one (more recent, more tested), explain why, and flag the other for cleanup. Don't blend conflicting patterns. Conformance to existing repo convention wins inside this codebase: if you think a convention is harmful, surface it; don't fork silently.

## 9. Keep the tracking docs current as work changes

The docs under `docs/` are the project's memory; treat them as part of the change. The root `AGENTS.md` hard rule covers the roadmap tick, the status line, and stale facts; also update any plan or checklist whose state changed. When a phase or plan fully ships, move its subplan to `docs/plans/archive/` and collapse its detail out of the living roadmap; the living docs should show what's left, not relitigate what's done. A doc that lies is worse than no doc: if you can't verify a claim, soften or flag it rather than leaving it stale.

## Working with CI

Never request human review on a red PR. CI path filters live inside the workflows (a `changes` job), so a docs-only PR skips the heavy jobs but still reports every required check; `ci-nightly.yml` runs both full suites against `master` as the backstop. Details per workflow are in `.github/README.md`.
