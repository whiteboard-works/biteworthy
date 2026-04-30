# Play Store metadata (Android)

Google Play Console → BiteWorthy → Main store listing.

## App name (30 char limit)

> BiteWorthy

## Short description (80 char limit)

> Scan any restaurant menu, see only the dishes you can actually eat.

## Full description (4000 char limit)

(Same body as `app-store.md` Description section — keep them in lockstep. Google's listing renders Markdown line breaks differently from Apple's, but the copy itself is identical.)

## Graphics

- **App icon** — 512×512 PNG (no transparency on Play). Generated from `apps/mobile/assets/icon-source.svg` (Phase 5.9-wiring follow-up); see `apps/mobile/assets/README.md`.
- **Feature graphic** — 1024×500 PNG. The hero panel ("Scan any menu...") with the BiteWorthy logo lockup.
- **Phone screenshots** — minimum 2, recommended 8. See `screenshots-plan.md`.
- **7-inch tablet** — optional; skip for v1 (mobile-only beta).
- **10-inch tablet** — optional; skip for v1.

## Categorization

- **Application type:** App
- **Category:** Food & Drink
- **Tags:** Healthy Lifestyle, Restaurant Finder

## Contact details

- **Email:** hello@bite-worthy.com
- **Phone:** _omit until we have a support number_
- **Website:** https://bite-worthy.com/
- **Privacy Policy:** https://bite-worthy.com/privacy

## Content rating

- **IARC questionnaire:** Everyone (no violence, no drugs, no purchases inside the app, no user-generated content visible to all)
  - User-generated content: Yes (reviews) — moderated through Phase 4.6's queue. The questionnaire asks about UGC visibility; reviews are visible to all signed-in users.

## Data safety

Mirrors `app-store.md`'s App Privacy answers. The Play data-safety form has separate questions for "data collected" vs "data shared"; we **collect** the data listed in the privacy policy and **share** none of it (Anthropic + Postmark + R2 + PostHog are processors, not third-party recipients in the Play sense — the form has a "service provider" exception).

## Pricing & distribution

- **Price:** Free
- **Countries:** US-only at launch (Phase 6+ adds others as the funnel proves out).
- **In-app purchases:** No.
- **Ads:** No.
- **Content guidelines:** Family-friendly; no restricted content.
- **US export laws:** App does not contain encryption requiring a registration. (Standard HTTPS to our API only.)
