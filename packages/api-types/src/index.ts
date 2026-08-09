/**
 * BiteWorthy API types.
 *
 * The bulk of this package is auto-generated from `docs/openapi.json`
 * (which itself is built from rswag specs in apps/api/spec/integration/).
 * Re-run `pnpm --filter @biteworthy/api-types build:codegen` after any
 * Rails endpoint change. CI's `codegen:check` script fails the build
 * if `src/generated.ts` is out of sync with the spec.
 *
 * Two hand-written enums remain at the bottom: `Confidence` and
 * `Strictness`, which `@biteworthy/filter-engine` re-exports as the
 * canonical wire enums. The hand-written `Ingredient` / `Tag` /
 * `Restaurant` / `Item` / `UserProfile` read models that used to sit
 * beside them are gone — nothing imported them, and they had drifted
 * into fiction (camelCase against a snake_case wire, a `path` Rails
 * never emits, a `cityId` that is really a nested `city`). Anything
 * that needs those shapes should come from the generated components,
 * which means giving the endpoint an rswag spec first.
 */

export type * from './generated';
export type { paths, components, operations } from './generated';

import type { components } from './generated';

// Friendly aliases for the most-used component schemas. Consumers
// shouldn't have to spell out `components["schemas"]["..."]` everywhere.
export type UserPayload    = components['schemas']['UserPayload'];
export type AuthResponse   = components['schemas']['AuthResponse'];
export type ProfilePayload = components['schemas']['ProfilePayload'];
export type IngredientRef  = components['schemas']['IngredientRef'];

// Chat + MCP. Anchored here so the web and mobile clients import the
// generated shape rather than hand-writing one that can drift from the
// API — `codegen:check` in ci-js.yml fails if these stop matching the
// rswag specs they came from.
export type Conversation   = components['schemas']['Conversation'];
export type ChatMessage    = components['schemas']['ChatMessage'];
export type ChatBlock      = components['schemas']['ChatBlock'];
export type PendingTool    = components['schemas']['PendingTool'];
export type ChatUsage      = components['schemas']['ChatUsage'];
export type ChatEventsPage = components['schemas']['ChatEventsPage'];
export type Attachment     = components['schemas']['Attachment'];
export type McpToken       = components['schemas']['McpToken'];
export type TagRef         = components['schemas']['TagRef'];

// ---- Canonical filter enums (hand-written; not yet codegen'd) ----
//
// `item_ingredients.confidence` / `user_profiles.strictness` in the
// schema. Adding a value here without adding it to the Rails enum
// (or vice versa) is the drift `codegen:check` cannot catch, since
// these have no component schema behind them yet.

export type Confidence = 'confirmed' | 'suggested' | 'inferred';

export type Strictness = 'relaxed' | 'balanced' | 'strict';
