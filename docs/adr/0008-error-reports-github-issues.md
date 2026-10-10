# ADR 0008: error reports as GitHub issues

- **Date:** 2026-10-10
- **Status:** Accepted
- **Refines:** [ADR 0001](./0001-stack.md) (the stack line "Errors | Sentry" — never wired)

## Context

ADR 0001 named Sentry for errors. Nothing was ever wired: no gem, no DSN, no `Rails.error` subscriber. The chat loop, the tool layer, and the controllers all call `Rails.error.report` on the failures they catch, and Rails itself reports unhandled request exceptions and exhausted job failures the same way (through the executor Solid Queue wraps every job in) — but `ActiveSupport::ErrorReporter#report` with no subscribers does nothing. Every one of those calls was a no-op, and the only trace of a production failure was a log line on the Hetzner box that nobody reads until a user writes in.

The question was where the reports should go. Options weighed:

- **Sentry (or any hosted tracker).** Real product, real cost, a fourth vendor holding stack traces and conversation ids, and a dashboard that would be opened when something was already known to be wrong.
- **Linear.** The portfolio's Linear rules are explicit: Linear holds decisions and results, bugs that need code are GitHub issues, and nothing posts progress pings there. An automated error feed is the thing those rules exist to keep out.
- **GitHub issues.** Where bugs already live, where the fix's PR links back, free, and already reachable from every agent and from the `gh` CLI. The only thing it lacks is deduplication, which is a table and a fingerprint.

## Decision

A `Rails.error` subscriber (`ErrorReports::Subscriber`, registered in `config/initializers/error_reports.rb`) queues `ErrorReports::FileIssueJob` for every reported error — at most once per fingerprint per five seconds per process, with the rest of a burst folded into that one as a count (`ErrorReports::Throttle`). The job:

1. **Counts it on `error_reports`** — one row per fingerprint, which is the error class, the message with ids, emails, quoted strings, measurements and long numbers blanked, and the first app frame without its line number. A thousand occurrences of one bug are one row with a count.
2. **Files or updates one GitHub issue per row** (`ErrorReports::GithubIssues`). First occurrence opens it with the message's *shape* (the same blanked form, never the raw text, which may quote what a person typed), the scalar context, and the app-frame backtrace. Later occurrences add a comment with the count, at most once an hour; whatever arrives inside that hour books one catch-up sync for when it ends, so a recurrence ten minutes after a close is not lost. The target repo is checked to be private before anything is filed. A closed issue that fires again is reopened — a fix that did not take is the point — unless it carries the `wontfix` label, which mutes it: counted, never touched again. A deleted issue is replaced; a refused request gives the hourly slot back; at most twenty new issues open per hour across all fingerprints.

The subscriber only queues a job and never raises; the job never raises; the job that files issues ignores its own failures. Those are what make it safe to subscribe in every environment.

**The target repo is configuration, and it must be private.** `whiteboard-works/biteworthy` is public, and an issue still carries a backtrace and a conversation id. Until `GITHUB_ERROR_REPORTS_TOKEN` and `GITHUB_ERROR_REPORTS_REPO` are set, nothing is filed and every failure still lands in `error_reports` for the day they are. `docs/launch-readiness.md` §11 is the human checklist.

What now reports, beyond what already did: the chat's upstream, stream, pane, compaction, regrounding, repair, and naming rescues, all of which previously only logged. `ApplicationJob`'s retries are deliberately *not* reported: the executor already reports the exhausted failure, and reporting each attempt would count one dead job three times and reopen issues on transient blips.

## Consequences

- No Sentry, no new vendor, no cost. The count lives in Postgres and the conversation lives on GitHub.
- An upstream outage (a run of 529s) opens one issue, not fifty — but it does open one. That is deliberate: a rate limit that recurs daily is a problem to fix, and `wontfix` is one click.
- The raw message stays in Postgres, next to the transcripts it may quote. Whether the private repo should be named in `/privacy` as somewhere a backtrace and conversation id can go is an open question for the L1 review, not something this ADR settles.
- Client-side errors are out of scope. PostHog's `capture_exceptions` is off in `apps/web` on purpose (exception payloads carry data `/privacy` does not disclose), and the chat's failures are classified server-side anyway.
- Rotating the token is a `.kamal/secrets` edit plus `bin/kamal-secrets-push`, like any other secret.
