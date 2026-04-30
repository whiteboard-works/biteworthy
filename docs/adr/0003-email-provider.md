# ADR 0003: production email (Postmark via SMTP)

- **Date:** 2026-04-30
- **Status:** Accepted
- **Refines:** ADR 0001 (the stack pick named SMTP-as-pluggable but didn't pick a provider)

## Context

Phase 4 shipped three mailer surfaces with `:test` adapter only:
- Devise password reset (built-in `Devise::Mailer.reset_password_instructions`)
- Phase 4.9's `RestaurantClaimMailer.verify_email`
- Phase 4.6 moderation notifications (currently log-only)

Phase 5.2 lights up real delivery. The pick has to clear three bars:

1. **Reliability** — review/claim/password-reset emails are conversion-critical. Bouncing or going to spam costs real users.
2. **Operational simplicity** — the loop should be able to ship the wiring; only credential drop should need a human.
3. **Cost at launch volume** — Durango beta projects ~50–500 emails/month for the first quarter. Free tier or sub-$10/mo is the target.

## Decision

**Postmark, accessed via plain SMTP** (no custom gem).

### Why Postmark over the alternatives

| Provider | Why considered | Why not picked |
|---|---|---|
| **Postmark** | Best deliverability for transactional in industry surveys. Free tier: 100 emails/mo; $15/mo for 10k. Dedicated transactional product (no marketing-spray UI). | — picked. |
| AWS SES | Cheapest at scale ($0.10 / 1k). Strong infra. | Higher operational ceiling: needs sandbox-mode escape, DKIM setup is more involved, deliverability history is owned by AWS not us. Worth revisiting if Postmark cost ever bites at >100k/mo. |
| SendGrid | Generous free tier. | Deliverability has slipped per the same surveys. UI heavily pushes marketing features we don't want. |
| Mailgun | Reasonable middle ground. | No free tier anymore. Pricing comparable to Postmark with worse deliverability reputation. |
| Resend | New + dev-friendly. | Too young for transactional reliability claims at v1. Revisit Phase 6+. |

### Why SMTP, not the `postmark-rails` gem

- **Provider portability.** SMTP is the universal protocol; switching providers is a `fly secrets set SMTP_*=...` away. The `postmark-rails` gem locks every mailer's `delivery_method` to `:postmark` and adds a Mail::Postmark gem dep.
- **No new gems.** Rails ships the SMTP delivery method out of the box. Less surface to upgrade across Rails versions, less Bundler audit churn.
- **Postmark's REST API isn't worth the complexity here.** The REST API gives back per-message metadata (open/click) that we don't need for transactional. SMTP returns a Message-ID which is enough to grep `fly logs` if a delivery is questioned.

If a future phase needs Postmark's tag-based analytics or template engine, swapping in `postmark-rails` is a one-PR operation.

### What this PR ships

- `config/environments/production.rb` — `delivery_method = :smtp`,
  `smtp_settings` reading `SMTP_ADDRESS / SMTP_PORT / SMTP_USERNAME /
  SMTP_PASSWORD / SMTP_DOMAIN`, defaults to `smtp.postmarkapp.com:587`
  + STARTTLS + plain auth (Postmark's recommended config).
- `default_url_options` derived from `MAILER_HOST` (defaults to
  `https://bite-worthy.com`) so mailer-rendered URLs (verify links,
  password resets) work.
- `BiteworthyMailer.smoke_test(to:)` + text/html templates — a
  self-contained, no-DB-record-needed smoke message.
- `Biteworthy::EmailSmoke` runner (`app/services/biteworthy/`) +
  `bin/rails biteworthy:email:smoke EMAIL=...` rake adapter. Reports
  the SMTP Message-ID per delivery; exits non-zero on failure when
  `EXIT_CODE=1` is set so CI can fail a deploy.
- `.env.example` adds the SMTP_* placeholders + MAILER_HOST.
- This ADR.

### What needs a human (Phase 5.2 acceptance criterion)

The acceptance ("a human runs `email:smoke EMAIL=...` and receives the message") needs:

1. Sign up for Postmark (https://postmarkapp.com), create a "BiteWorthy" server in transactional mode.
2. Verify the `bite-worthy.com` sender domain (DKIM + Return-Path DNS records — same registrar as the API CNAME from Phase 5.1).
3. Generate a Postmark **Server API Token** (used as both SMTP user_name and password).
4. `fly secrets set \
       SMTP_ADDRESS=smtp.postmarkapp.com \
       SMTP_PORT=587 \
       SMTP_USERNAME=$POSTMARK_TOKEN \
       SMTP_PASSWORD=$POSTMARK_TOKEN \
       SMTP_DOMAIN=bite-worthy.com \
       MAILER_HOST=https://bite-worthy.com`
5. `fly ssh console -C 'bin/rails biteworthy:email:smoke EMAIL=skylar@gmail.com'`.

Steps 1–3 are one-time; 4 happens on token rotation; 5 is the test.

### Phase 4 mailer surfaces — what works after this lands

- **Devise password reset** — automatic. Devise issues a token, the built-in `Devise::Mailer.reset_password_instructions` renders against `default_url_options`, SMTP delivers.
- **`RestaurantClaimMailer.verify_email`** — automatic. The mailer already builds the verify URL itself (Phase 4.9's controller passes it in); SMTP just carries it now.
- **Review confirmations** — Phase 4.3 chose not to send a confirmation on review create (only on flag/hide later via the moderation queue). Out of scope here; if a confirmation is desired, it's a separate one-line mailer.

## Trade-offs

**Cost ceiling** — Postmark $15/mo at 10k mails. If Phase 5.7's seed run plus organic signups push us past 10k/mo, revisit SES (cost gap becomes meaningful at ~50k/mo).

**Single provider** — no failover. If Postmark has a regional outage, mail queues in Solid Queue (mailer jobs auto-retry). Multi-provider failover is Phase 6+ work.

**SMTP password = API token** — Postmark's pattern (no separate username). Token rotation = `fly secrets set` + Fly rolling restart.

## Consequences

- **Operational simplicity** — one provider, one set of env vars, one ADR.
- **Vendor lock-in for analytics only** — base SMTP delivery is portable; if we ever instrument open/click tracking via Postmark headers, that becomes provider-specific.
- **Mailer template work has no Postmark-specific assumptions** — text + html parts, layout in `app/views/layouts/mailer.html.erb`, all standard Rails. Future Phase 6+ analytics (PostHog Email if it exists, Customer.io) plug in the same way.
