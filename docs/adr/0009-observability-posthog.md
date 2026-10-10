# ADR 0009: observability on PostHog — events, errors, and logs in one project

- **Date:** 2026-10-10
- **Status:** Accepted
- **Refines:** [ADR 0006](./0006-analytics.md) (which project the clients report to), [ADR 0007](./0007-hosting-kamal-hetzner-neon.md) (its "logs do not outlive a deploy" note), [ADR 0001](./0001-stack.md) (the stack line "Errors | Sentry")

## Context

Three gaps, found the same week:

1. **No funnel data had ever arrived.** The web and mobile wiring from Phase 5.8 was complete, but it read its key from an environment variable that was never set, and the project it was documented against — the Whiteboard Works cross-product project, id 370116 — is shared with six browser extensions and filtered by a super property. BiteWorthy has its own project now: **652080**, "no events yet" on the day of this ADR.
2. **The API's logs vanish on deploy.** `kamal app logs` reads the running container; a deploy replaces both role containers; the Jev shadow trial lost 13 of 16 runs' lines that way (ADR 0007, roadmap 2026-10-10).
3. **The API's errors go nowhere.** `Rails.error.report` is called from the chat loop, the tool layer, and the controllers, and Rails reports unhandled request and job failures to it as well — with no subscriber on `master`, every call is a no-op. (A subscriber that files deduplicated GitHub issues is in flight on a separate branch; it and this ADR are complementary, and both can subscribe.)

PostHog was already the analytics vendor (ADR 0006), already a named subprocessor in `/privacy`, and now has error tracking and a logs product on the same project token. One more vendor for errors and another for logs would mean two more dashboards nobody opens and two more places a conversation id can end up.

## Decision

**One PostHog project, 652080, receives everything the product emits about itself:** the funnel events from web and mobile, the exceptions from the Rails API and the Next server, and the API's and the Next server's logs.

### Where the key lives

The project token (`phc_…`) is PostHog's public client token — it is write-only and designed to ship in every browser bundle. It is therefore **configuration, not a secret**, and it is pinned in code and config rather than in dashboard variables, which is where the previous key sat unset for five months:

- **Web:** `apps/web/src/lib/posthog-config.ts`. On `bite-worthy.com` / `www.bite-worthy.com` the browser uses the token unconditionally; on Vercel's production deployment (`VERCEL_ENV=production`) so does the server. Everywhere else, `NEXT_PUBLIC_POSTHOG_KEY` decides and unset means off, so a laptop or a preview deploy sends nothing unless asked.
- **Mobile:** `EXPO_PUBLIC_POSTHOG_KEY` in `apps/mobile/eas.json`'s `production` profile only, the same way the API base is set; preview builds are QA traffic and must not land in the launch funnels. Mobile stays opt-in by default.
- **API:** `POSTHOG_API_KEY` in `apps/api/config/deploy.yml`'s `env.clear`, with `APP_ROLE` (`web` | `worker`) set per role so every record says which container it came from. Unset — development, CI, a clone — and the client is disabled; nothing below needs an environment check.

### What each surface sends

| Surface                  | Events                                                       | Exceptions                                                                                                                                                                         | Logs                                                                                                                                                             |
| ------------------------ | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Browser (`apps/web`)     | The named funnel events and scrubbed `$pageview`s, as before | **No.** `capture_exceptions` stays off; see below                                                                                                                                  | No                                                                                                                                                               |
| Mobile (`apps/mobile`)   | The named funnel events, opt-in                              | No                                                                                                                                                                                 | No                                                                                                                                                               |
| Next server (`apps/web`) | No                                                           | **Yes.** `src/instrumentation.ts` → `onRequestError` → `posthog-node` `captureExceptionImmediate`                                                                                  | **Yes.** `lib/server-log.ts` → OTLP → PostHog Logs, `service.name = biteworthy-web`; used for an upstream 5xx from Rails and the clamped forgot-password failure |
| Rails API (`apps/api`)   | No                                                           | **Yes.** `posthog-rails`: every `Rails.error.report`, every unhandled request exception, every job that exhausted its retries (reported by the executor Solid Queue wraps jobs in) | **Yes.** `Rails.logger` broadcast to PostHog Logs over OTLP, info and up, `service.name = Biteworthy`                                                            |

### What is deliberately kept out

The posture `/privacy` already takes for client events — a random id, nothing that names a person or a diet — applies to the server side too:

- **No identity on a server error.** `capture_user_context` and `use_tracing_headers` are off in the API; the Next server passes no distinct id. The SDKs fill in a random one with no person profile.
- **No request body, no caller address.** `Telemetry::Scrub.event` drops `$request_params` (the body after the parameter filter — which cannot see inside a chat message or a review, either of which can name a diet) and `$ip`. The Next server's `requestErrorProperties` never reads headers or cookies, keeps the path only, and masks `/durango/<diet>` and `/u/<handle>` the way page views already are.
- **Logs are scrubbed before they leave.** `Telemetry::Scrub.log` drops Rails' `Parameters:` line outright (a chat message or a review sits under keys the parameter filter does not name), drops the `/up` health-check lines (`silence_healthcheck_path` silences STDOUT only; the forwarder is a plain Logger without silence), blanks the client address on Rails' request line (IPv6 included), IPv4 addresses and emails anywhere, a token in any query string (verify links, resets, share links), every job's logged arguments (Devise's mail job carries the raw reset token as a bare string), what the grounding reviewer said about an answer (the one log line that quotes model text about a person's turn), and anything shaped like a credential: the key prefixes the app holds, bearer tokens, JWTs, Resend keys, the password in a connection URL. posthog-rails caps forwarding at 6,000 records a minute. The Next server's `sanitizeError` runs the same scrubs over an exception's message and cause chain before `posthog-node` serializes it.
- **Rescued errors are not errors.** A 404 or a 422 that a controller renders is not reported (`report_rescued_exceptions` off). `ApplicationJob`'s retries are not reported per attempt (`auto_instrument_active_job` off) — the exhausted failure is, once. An explicit `Rails.error.report` is always reported: posthog-rails' subscriber skips reports made during a request (it expects its middleware to see the exception, which a handled report never raises), so `Telemetry::ErrorSubscriber` takes exactly those and nothing else.
- **The query string never leaves either.** Rails logs `filtered_path`, so `profile`, `strictness`, and `q` join `filter_parameters`; `/api/v1/users/<handle>` is masked in logs and reports like `/u/<handle>` is in page views.
- **Browser and mobile exceptions stay off.** An exception payload carries a message and a stack, and neither is something `/privacy` discloses. Turning them on is a product call that goes with a privacy-page change and the L1 review, not a config flip.

### Reading it

- **Logs:** PostHog → Logs. Filter `service.name` (`Biteworthy` for Rails, `biteworthy-web` for Next) and `service.role` (`web`, `worker`); `url.path` and `http.request.method` are on every Rails line emitted inside a request.
- **Errors:** PostHog → Error tracking. `$exception_source` is `rails`, `rails_error_reporter`, or `nextjs-server`; `$context_component` carries what `Rails.error.report` was given (`chat`, a tool name, a job).
- **Events:** as before, with no `extension` filter needed any more (the property is still sent so saved insights keep working).

## Consequences

- **The privacy page names one more use of the same processor.** PostHog's subprocessor entry now says it also receives error reports and logs from our servers. That is a factual change to a legal page; it is flagged for the L1 review rather than settled here.
- **No new vendor, no new secret.** The token is public; rotating it is a config change in three files. Cost stays inside PostHog's free tier at launch volume; the per-minute cap bounds a runaway logger.
- **`extension: 'biteworthy'` is now redundant** and kept only for the saved insights that filter on it. Drop it when those are rebuilt against the new project.
- **Two error subscribers may coexist.** When the GitHub-issues reporter lands, a failure is both an issue to fix and a PostHog event to trend; the fingerprinting there and the grouping here are independent, and that is fine.
- **The PostHog MCP server configured for agents has an invalid token** (every call fails `INVALID_API_KEY`), so dashboards, alerts, and verification happen in the UI until it is re-authorized.
