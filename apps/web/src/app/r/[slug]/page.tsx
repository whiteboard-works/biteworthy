/**
 * Phase 3.9 — short share-link route. `/r/<slug>?p=<token>` is the
 * URL the Share button generates; we re-export the same SSR page
 * Phase 3.6 ships at `/restaurants/<slug>` so both paths render
 * identically. Keeps the share URL short for SMS / clipboard.
 */
// generateMetadata rides along so every /r/<slug>?p=… variant (now a 200
// even when the token is dead) collapses onto the bare menu's canonical.
export { default, generateMetadata } from '../../restaurants/[slug]/page';
