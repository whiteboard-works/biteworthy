# BiteWorthy mobile — store listing

The metadata Apple and Google show on the App Store and Play Store. Phase 5.9 ships these as drafts; the wiring follow-up tightens copy + uploads them.

## Files

- `app-store.md` — App Store Connect metadata (iOS).
- `play-store.md` — Google Play Console metadata (Android).
- `screenshots-plan.md` — what each marketing screenshot needs to show, plus the expo-router test routes that drive them.

## Update flow

1. Edit the markdown here.
2. Re-run `eas submit --platform=all` after the next build (Phase 5.9-wiring follow-up automates this on tag).
3. The Phase 5.10 press kit references the same copy verbatim — keep them in sync.

## Source of truth

The hero copy on `apps/web/src/app/page.tsx` (Phase 5.5) is canonical for the **value prop sentence** ("Scan any menu, see only what you can eat."). When that changes, propagate here + on the website's OG card.
