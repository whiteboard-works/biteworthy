# BiteWorthy mobile — store listing

The metadata Apple and Google show on the App Store and Play Store. Drafts until the first store submission, which is still a human step (see `docs/launch-readiness.md`).

## Files

- `app-store.md` — App Store Connect metadata (iOS).
- `play-store.md` — Google Play Console metadata (Android).
- `screenshots-plan.md` — what each marketing screenshot needs to show, plus the expo-router test routes that drive them.

## Update flow

1. Edit the markdown here.
2. Re-run `eas submit --platform=all` after the next build.
3. The press page at bite-worthy.com/press carries the same copy — keep them in sync.

## Source of truth

The hero copy on `apps/web/src/app/page.tsx` is canonical for the **value prop sentence** ("Scan any menu, see only what you can eat."). When that changes, propagate here + on the website's OG card.
