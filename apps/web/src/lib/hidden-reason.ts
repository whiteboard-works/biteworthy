/**
 * Phase 3.6 — translate the {kind, *_id, *_name, *_family} reason
 * shape into a human chip label. Mirror of the mobile helper at
 * apps/mobile/lib/hidden-reason.ts. Kept duplicated until a future
 * refactor extracts it into a shared package.
 */
import type { HideReason } from './restaurants';

function humanizeFamily(family: string | null | undefined): string {
  if (!family) return 'restricted';
  return family.replace(/_/g, ' ');
}

export function hiddenReasonLabel(reason: HideReason): string {
  switch (reason.kind) {
    case 'avoid_ingredient': {
      const family = humanizeFamily(reason.ingredient_family);
      const name = reason.ingredient_name ?? 'ingredient';
      return `Contains ${family} (${name})`;
    }
    case 'avoid_tag': {
      const family = humanizeFamily(reason.tag_family);
      const name = reason.tag_name ?? 'tag';
      return `Tagged ${family}: ${name}`;
    }
    case 'unconfirmed_strict':
      return `AI confidence: ${reason.confidence} (strict mode)`;
  }
}
