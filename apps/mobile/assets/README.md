# BiteWorthy mobile — assets

Binary assets the app bundle ships, rendered from the SVG sources here.

**Current icon is the "B" (plate) placeholder** — white ground, brand-red
plate, white "BW", a bite out of the corner — chosen to ship something now and
slated for a redraw. Sources: `icon-source.svg` (iOS icon + web + favicon),
`adaptive-foreground.svg` (Android), `splash-source.svg` (launch). Wired in
`app.json`; web favicons land in `apps/web/src/app/{icon,apple-icon}.png` (Next
App Router auto-links them). Regenerate with `pnpm mobile render:assets`.

## Required for store submission

| File | Size | Notes |
|---|---|---|
| `icon.png` | 1024×1024 | App icon. No transparency. Apple expects square corners; the OS rounds them. Background must be a solid color (`colors.bite` = `#E14E2A` is the brand pick — see `packages/ui-tokens`). |
| `adaptive-icon.png` | 1024×1024 | Android adaptive icon foreground. Center logo within the safe zone (66% of the canvas). Background color set via `app.json`'s `expo.android.adaptiveIcon.backgroundColor` to `colors.bite`. |
| `splash.png` | 1284×2778 | iOS launch screen + Android splash. Centered logo lockup on `colors.bite`. |
| `favicon.png` | 48×48 | Web fallback (Expo router web). |

## Generation flow (Phase 5.9-wiring)

1. **Source vector:** `apps/mobile/assets/icon-source.svg`
   - "BW" monogram or full lockup, depending on size.
   - Single fill: `var(--bite, #E14E2A)`.
   - 1024×1024 viewBox so all PNG variants downscale cleanly.

2. **Render pipeline:** `apps/mobile/scripts/render-assets.mjs` shells out to
   `rsvg-convert` (librsvg) — it rasterizes the SVG's "BW" text reliably via
   Pango, no native-module install or font-outlining step (macOS:
   `brew install librsvg`). Run with `pnpm mobile render:assets`.

3. **Commit the rendered PNGs.** They're tiny (under 50KB each).
   The SVG source is the master; the PNGs are derived but checked in
   so EAS builds don't need a render step.

## Color reference (from `@biteworthy/ui-tokens`)

```
bite:        #E14E2A   (primary brand red)
biteDark:    #A8351A   (hover / pressed state)
biteLight:   #FFE9E1   (background / chip fill)
bg:          #FFFFFF   (white surface)
text:        #1A1A1A   (near-black)
```

The icon should use `bite` as the hero color. Don't introduce new colors here; ui-tokens is the single source of truth (Phase 0 ADR 0001).
