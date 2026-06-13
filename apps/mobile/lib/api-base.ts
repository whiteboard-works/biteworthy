/**
 * The origin of the BiteWorthy Rails API.
 *
 * Single source of truth: every `lib/api/*` fetch helper and the auth
 * module import this instead of re-deriving it. Defaults to the local
 * API on :3000; a build sets `EXPO_PUBLIC_API_BASE` to the deployed
 * origin (and, for a physical device, the machine's LAN IP).
 */
export const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';
