/**
 * BiteWorthy API types.
 *
 * The bulk of this package is auto-generated from `docs/openapi.json`
 * (which itself is built from rswag specs in apps/api/spec/integration/).
 * Re-run `pnpm --filter @biteworthy/api-types build:codegen` after any
 * Rails endpoint change. CI's `codegen:check` script fails the build
 * if `src/generated.ts` is out of sync with the spec.
 *
 * The hand-written domain types below are read-model shapes used by
 * `@biteworthy/filter-engine` and by ad-hoc client code. They stay
 * until ingredient / tag / restaurant list endpoints get their own
 * rswag specs (which would then generate them as components). Phase
 * 1.7 added `/restaurants/:id/items` but inlined the item shape in
 * the operation response rather than exposing it as a component.
 */

export type * from './generated';
export type { paths, components, operations } from './generated';

import type { components } from './generated';

// Friendly aliases for the most-used component schemas. Consumers
// shouldn't have to spell out `components["schemas"]["..."]` everywhere.
export type UserPayload    = components['schemas']['UserPayload'];
export type AuthResponse   = components['schemas']['AuthResponse'];
export type ProfilePayload = components['schemas']['ProfilePayload'];

/**
 * The shape `filter-engine` cares about — a subset of ProfilePayload
 * with snake_case names mapped over for ergonomic JS usage.
 * Slated to be replaced when Phase 1.7 lands the filter SQL endpoint.
 */
export interface UserProfile {
  avoidIngredientIds: string[];
  avoidTagIds: string[];
  preferTagIds: string[];
  strictness: Strictness;
}

// ---- Hand-written read-model types (slated for codegen in Phase 1.7) ----

export type Confidence = 'confirmed' | 'suggested' | 'inferred';

export type Strictness = 'relaxed' | 'balanced' | 'strict';

export interface Ingredient {
  id: string;
  slug: string;
  name: string;
  path: string;
  aliases: string[];
}

export interface Tag {
  id: string;
  slug: string;
  name: string;
  family: 'diet' | 'allergen' | 'cuisine' | 'prep' | 'flavor';
  path: string;
}

export interface Restaurant {
  id: string;
  slug: string;
  name: string;
  cityId: string;
  website: string | null;
  status: 'draft' | 'published' | 'closed';
}

export interface Item {
  id: string;
  restaurantId: string;
  name: string;
  description: string | null;
  ingredientIds: string[];
  tagIds: string[];
  confidence: Confidence;
}
