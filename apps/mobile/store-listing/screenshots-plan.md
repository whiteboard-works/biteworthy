# Screenshot plan

5 screenshots per device class, captured against the seeded Durango restaurants from Phase 5.7. Produced in Phase 5.9-wiring (this PR ships only the plan).

## Required device classes

- **iOS 6.7" (iPhone 15 Pro Max)** — Apple's primary marketing surface. Required.
- **iOS 6.1" (iPhone 14 Pro)** — fallback. Required.
- **Android phone, portrait, 16:9 or 9:16** — required.

iPad screenshots are optional and skipped for v1 (mobile-only beta).

## The 5 shots, in order (the App Store Connect "App Previews" carousel renders them this way)

1. **Hero — restaurant page filtered.**
   "Cream, Bean & Berry" with a Celiac filter applied. 7 visible dishes, 4 hidden with "Contains gluten (wheat)" chips. Caption: *Find what you can eat.*

2. **Onboarding — 6 taps.**
   The preset picker mid-tap (Celiac highlighted). Caption: *Six taps to a working filter.*

3. **Hidden item explainer.**
   Detail view of a hidden dish with the chip expanded ("Contains shellfish — Crab Rangoon"). Caption: *Every hidden dish says why.*

4. **Show anyway override.**
   Same restaurant page after tapping "show anyway" on one item. Caption: *Override per meal, or set permanent rules.*

5. **Reviews + dish photo.**
   An item detail screen with a 4-star review + a real cropped dish photo (Phase 4.11 / Phase 5.7 seed produces these). Caption: *Real reviews from people who eat the way you do.*

## How to capture

Phase 5.9-wiring follow-up adds expo-router test routes at `/screenshots/<id>` that drive each screen with deterministic seed data. Capture flow:

```bash
# in apps/mobile
EXPO_USE_DEV_SERVER=false eas build --profile preview --platform all
# install the build on the simulator/emulator
xcrun simctl io booted recordVideo /tmp/cap.mov
# navigate via deep link: biteworthy://screenshots/1, /2, etc.
# extract frames at each route's stable position
```

Or just take real screenshots at the routes — the test routes guarantee the dishes shown are the same across builds.

## Localization

US English only at launch. Spanish + others ride the next round once the funnel proves out (Durango itself has a meaningful Spanish-speaking population — worth doing in Phase 6 even if the city stays the same).
