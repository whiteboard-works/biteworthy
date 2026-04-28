# BiteWorthy Mobile

Expo SDK 52 + expo-router. The diner-first surface — camera, filter,
scan-and-eat.

## Local

```bash
pnpm install                  # from repo root
pnpm mobile dev               # boots Expo Dev Tools
pnpm mobile ios               # iOS simulator (requires macOS + Xcode)
pnpm mobile android           # Android emulator
```

Use the Expo Go app on a physical device for the fastest iteration loop —
the camera capture flow needs a real camera anyway.

## Why Expo

- Camera, secure-store, OAuth, push, OTA updates — all built in.
- Same TS as `apps/web`; shared `packages/filter-engine` runs identically
  on both.
- EAS Build replaces wrestling with native toolchains for releases.

## Shared with web

`@biteworthy/api-types`, `@biteworthy/filter-engine`, `@biteworthy/ui-tokens`
live in `packages/` and feed both apps. Mobile maps tokens into
`StyleSheet.create`; web maps the same tokens into Tailwind.
