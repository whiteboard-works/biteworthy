# BiteWorthy mobile — assets

Binary assets the app bundle ships. Phase 5.9 documents the specs;
Phase 5.9-wiring follow-up generates the actual PNGs from the
ui-tokens-derived SVG sources.

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

2. **Render pipeline:** an `apps/mobile/scripts/render-assets.mjs` script
   uses `sharp` to convert the SVG into the four PNG sizes above.
   Run with `pnpm --filter @biteworthy/mobile run render:assets`.

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
