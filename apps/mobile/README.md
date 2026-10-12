# BiteWorthy Mobile

Expo SDK 56 + expo-router, iOS and Android. The diner's app: the same
account and the same filtered menus as the web, with the camera one tap away.

## Run it

```bash
pnpm install                  # from the repo root
pnpm mobile dev               # Expo dev tools
pnpm mobile ios               # iOS simulator (macOS + Xcode)
pnpm mobile android           # Android emulator
pnpm mobile test              # Jest
pnpm mobile typecheck && pnpm mobile lint
```

A physical device with Expo Go is the fastest loop, and the scan flow needs a
real camera anyway. Copy `.env.example` to `.env`: `EXPO_PUBLIC_API_BASE`,
`EXPO_PUBLIC_WEB_BASE`, and the PostHog key, which is opt-in.

## Screens

`app/index.tsx` is home (nearby restaurants, logos, Top Picks); restaurants
and items have their own screens; `chat.tsx` is the assistant, polling the
API's event log where the web streams it; `onboarding/` sets the avoid lists;
`settings/` holds the account, bio, saved chat notes, and home city.

This app **does not filter**. It renders the `status` and `reasons` the API
sends; `@biteworthy/filter-engine` gives it wire types and display helpers,
not a filter.

## Expo-managed dependencies

`expo-*`, `react-native`, and `jest-expo` versions belong to the SDK. Change
them only with `npx expo install --fix`; the monthly `expo-align` workflow
does the same and opens a PR when there is drift. Camera and image picking
come from `expo-camera` and `expo-image-picker`, the JWT lives in
`expo-secure-store`.

## Builds and the stores

Builds go through EAS (`@whiteboard-works/biteworthy`). The app is not yet in
the App Store or Play Store. Store copy and screenshot plans are in
`store-listing/`, the icon and splash sources in `assets/` (render with
`pnpm mobile render:assets`), and the remaining human steps in
[`docs/launch-readiness.md`](../../docs/launch-readiness.md).

## Shared with web

`@biteworthy/api-types`, `@biteworthy/filter-engine`, `@biteworthy/analytics`,
and `@biteworthy/ui-tokens` in `packages/` feed both apps. Mobile maps the
tokens into `StyleSheet.create`; web maps the same tokens into Tailwind.
