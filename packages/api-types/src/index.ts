/**
 * Generated TypeScript types for the BiteWorthy Rails API.
 *
 * Until the OpenAPI generator is wired up (see apps/api rswag config),
 * this file holds hand-written types for the few endpoints the web and
 * mobile apps already consume. Replace with generated output ASAP.
 */

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

export interface UserProfile {
  avoidIngredientIds: string[];
  avoidTagIds: string[];
  preferTagIds: string[];
  strictness: Strictness;
}
