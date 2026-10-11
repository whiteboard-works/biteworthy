# ADR 0008: error reports as GitHub issues

- **Date:** 2026-10-10
- **Status:** Accepted
- **Refines:** [ADR 0001](./0001-stack.md) (the stack line "Errors | Sentry" — never wired)
- **Alongside:** [ADR 0009](./0009-observability-posthog.md) (every exception to PostHog; this ADR adds one deduplicated issue per failure)

## Context

ADR 0001 named Sentry for errors. Nothing was ever wired: no gem, no DSN, no `Rails.error` subscriber. The chat loop, the tool layer, and the controllers all call `Rails.error.report` on the failures they catch, and Rails itself reports unhandled request exceptions the same way — but `ActiveSupport::ErrorReporter#report` with no subscribers does nothing. Jobs were worse off still: Solid Queue rescues a job's final exception inside the app executor and files a failed execution, so an exhausted job never reached `Rails.error` at all. Every one of those calls was a no-op, and the only trace of a production failure was a log line on the Hetzner box that nobody reads until a user writes in.

[ADR 0009](./0009-observability-posthog.md), decided the same day, subscribes posthog-rails so that every report becomes a PostHog `$exception`. That is a stream: every occurrence, searchable, with no notion of "the same bug again" beyond PostHog's own grouping, and nothing that lands where the fix's PR will link. The question here was where a *deduplicated* report — one place per failure, with a count — should go. Options weighed:

- **Sentry (or any hosted tracker).** Real product, real cost, a fourth vendor holding stack traces and conversation ids, and a dashboard that would be opened when something was already known to be wrong.
- **Linear.** The portfolio's Linear rules are explicit: Linear holds decisions and results, bugs that need code are GitHub issues, and nothing posts progress pings there. An automated error feed is the thing those rules exist to keep out.
- **GitHub issues.** Where bugs already live, where the fix's PR links back, free, and already reachable from every agent and from the `gh` CLI. The only thing it lacks is deduplication, which is a table and a fingerprint.

## Decision

A `Rails.error` subscriber (`ErrorReports::Subscriber`, registered in `config/initializers/error_reports.rb`) queues `ErrorReports::FileIssueJob` for every reported error — at most once per fingerprint per five seconds per process, with the rest of a burst folded into that one as a count (`ErrorReports::Throttle`). The job:

1. **Counts it on `error_reports`** — one row per fingerprint, which is the error class, the message's *shape*, and the first app frame without its line number. The shape is the message with ids, emails, quoted strings, parenthesised values, measurements and long numbers blanked (`ErrorReports::Capture.normalized`), and it is all that is stored: a parser or a constraint quotes whatever a person typed, and a row that belongs to no account must never hold it, because deleting the account could not reach it. A thousand occurrences of one bug are one row with a count.
2. **Files or updates one GitHub issue per row** (`ErrorReports::GithubIssues`). First occurrence opens it with that shape, the scalar context, and the app-frame backtrace — after looking for an issue that already carries the fingerprint, so a create whose response was lost is adopted on the retry rather than twinned. Later occurrences add a comment with the count, at most once an hour; whatever arrives inside that hour books one catch-up sync for when it ends, so a recurrence ten minutes after a close is not lost. The target repo is checked to be private before anything is filed, and again every hour. A closed issue that fires again is reopened — a fix that did not take is the point — unless it carries the `wontfix` label, which mutes it: counted, never touched again. A deleted issue is replaced; a row whose issue is in a previous target repo starts over in the new one; a refused request gives the hourly slot back; at most twenty new issues open per hour across all fingerprints.

The subscriber only queues a job and never raises; the job never raises; the job that files issues ignores its own failures. Those are what make it safe to subscribe in every environment.

**The target repo is configuration, and it must be private.** `whiteboard-works/biteworthy` is public, and an issue still carries a backtrace and a conversation id. Until `GITHUB_ERROR_REPORTS_TOKEN` and `GITHUB_ERROR_REPORTS_REPO` are set, nothing is filed and every failure still lands in `error_reports` for the day they are. `docs/launch-readiness.md` §11 is the human checklist.

What now reports, beyond what already did: the chat's upstream, stream, pane, compaction, regrounding, repair, and naming rescues, all of which previously only logged. `ApplicationJob` reports a job's failure once, from `after_discard`, when its retries are spent — Solid Queue never hands the exception to `Rails.error` itself — and `ActionMailer::MailDeliveryJob`, which is not an `ApplicationJob`, gets the same from `config/initializers/error_reports.rb`. Attempts that will be retried are not reported: that would count one dead job three times and reopen issues on transient blips. For the same reason `Ingestion::TagDeriver` no longer reports an allergen-strategy failure before re-raising it — a report marks the exception as reported, and the job layer could then never report the real one.

## Consequences

- No Sentry, no new vendor, no cost. The count lives in Postgres and the conversation lives on GitHub. PostHog (ADR 0009) still receives every occurrence as an `$exception`; the two subscribers do not see each other's failures (Rails rescues a subscriber's own error, and this one ignores reports from its own jobs).
- An upstream outage (a run of 529s) opens one issue, not fifty — but it does open one. That is deliberate: a rate limit that recurs daily is a problem to fix, and `wontfix` is one click.
- What a person typed reaches Postgres or GitHub only if an exception message carries it *unquoted and outside parentheses* — the shapes a parser, a constraint, or Postgres uses when quoting input are blanked, as are ids, emails, addresses, links, and credentials, but normalization is a set of patterns, not a boundary. The raw message exists in the process that raised it, in the log line it already wrote, and in the PostHog `$exception` ADR 0009 sends (scrubbed the same way, not normalized). What does leave the box in every case is a backtrace and a conversation id; whether the private repo should be named in `/privacy` for that is an open question for the L1 review, not something this ADR settles.
- A message whose variable parts carry the diagnosis (which row, which value) is harder to read from the issue. That is the trade: `kamal console` and the conversation id are the way back to the specifics.
- Client-side errors are out of scope. PostHog's `capture_exceptions` is off in `apps/web` on purpose (exception payloads carry data `/privacy` does not disclose), and the chat's failures are classified server-side anyway.
- Rotating the token is a `.kamal/secrets` edit plus `bin/kamal-secrets-push`, like any other secret.
