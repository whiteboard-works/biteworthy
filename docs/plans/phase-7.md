# Phase 7 — Close the real-world mobile scan loop (subplan)

Phase 7 makes the phone the primary instrument of the product vision:
stand in a restaurant, open the app, scan the menu, and minutes later
read a simplified menu filtered to *you*. Phase 6 opened the pipeline
to everyone; Phase 7 removes the remaining friction on the device.

**Demo at the end:** cold-start the app at a restaurant. Home screen
shows nearby/searchable restaurants and a big "Scan a menu" button.
The restaurant isn't listed → tap Scan → name it → photograph two
menu pages with the real camera → watch extraction progress → swipe-
verify → land on the filtered menu and pick dinner.

## Stop conditions specific to Phase 7

- Camera work needs a physical device to truly verify; CI can only
  cover the component contract with the camera module mocked. Note
  any "verified in simulator only" honestly in the PR body.
- If expo-camera's API in the installed SDK differs from what the
  skeleton assumed, fix the skeleton — don't pin an older camera lib.

## Tasks (one PR each)

### 7.1 — Wire the real camera capture

**Branch**: `claude/phase-7.1-camera-capture`

The Phase 2.6 screen (`apps/mobile/app/ingest/index.tsx`) has the
multi-page capture flow but the camera ref is a TODO.

- Wire `expo-camera` (`CameraView` + `useCameraPermissions`): request
  permission with a friendly rationale state, capture stills via the
  ref, append to the existing multi-page thumbnail strip, retake per
  page.
- Permission-denied state links to system settings.
- Keep the existing upload path (`lib/api/ingestion-runs.ts`)
  untouched.

Specs (jest, camera module mocked): permission flow states, capture
appends a page, retake replaces, upload invoked with all pages.

### 7.2 — Real mobile home screen

**Branch**: `claude/phase-7.2-mobile-home`

Replace the placeholder `apps/mobile/app/index.tsx`:

- Restaurant search (name, against `GET /api/v1/restaurants` —
  add a `?q=` ilike/trigram param to the endpoint if it lacks one;
  rswag + openapi-export + codegen if the API changes).
- "Near me" section when location permission granted (sort by
  distance using address lat/lng already in the schema; graceful
  fallback to the city list without permission).
- Primary CTA: "Scan a menu" → `/ingest`.
- Profile entry point (onboarding if no profile yet, else summary).

Specs: search debounce + result rendering, no-permission fallback,
CTA navigation.

### 7.3 — Stitch the scan-to-menu flow

**Branch**: `claude/phase-7.3-scan-flow-stitch`

The end-to-end ribbon tying 6.6 + 7.1 + 7.2 together:

- From home search: "Can't find it? Scan it" empty-state action →
  new-restaurant form (Phase 6.6) → camera (7.1) → run progress
  screen (poll status with the existing pattern; show stage names
  extracting/resolving/staged) → swipe-verify → on publish,
  deep-link to `/restaurants/[id]` showing the user's own filtered
  view of the menu they just scanned.
- Re-scan entry: on an existing restaurant's menu screen, an
  overflow action "Menu changed? Re-scan" creating a new run against
  that restaurant (Phase 6.2's ownership rules apply).
- Fire the funnel events that already exist for these surfaces.

Specs: navigation-flow test with mocked API (happy path reaches the
restaurant screen), progress screen state mapping, re-scan entry
creates a run against the right restaurant id.

## Out of scope for Phase 7

- iPad/tablet layouts.
- Offline capture queueing.
- Menu-diff merging on re-scan (see Phase 6 out-of-scope note).
