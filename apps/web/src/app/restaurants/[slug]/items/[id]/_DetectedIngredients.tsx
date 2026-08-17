import type { DetectedAssociation, DetectedIngredient } from '../../../../../lib/restaurants';

/**
 * The provenance panel — what the AI (or a human) recorded for this
 * dish, association by association. This is the surface the story page
 * promises ("behind each call is a confidence level and a source"):
 * `confidence` and `source` render verbatim, never summarized away, so
 * a user can see whether "no gluten flagged" means "a human checked"
 * or "extracted and awaiting review". Glosses match the `explain_item`
 * MCP tool so both surfaces tell the same story.
 */

const CONFIDENCE_GLOSS: Record<DetectedAssociation['confidence'], string> = {
  confirmed: 'a human verified it',
  suggested: 'extracted, awaiting review',
  inferred: 'derived from other data',
};

const CONFIDENCE_MARK: Record<DetectedAssociation['confidence'], string> = {
  confirmed: '✓',
  suggested: '~',
  inferred: '≈',
};

export default function DetectedIngredients({
  ingredients,
  tags,
}: {
  ingredients: DetectedIngredient[];
  tags: DetectedAssociation[];
}) {
  return (
    <section aria-labelledby="detected-heading" className="mt-bw-8">
      <h2 id="detected-heading" className="text-bw-lg font-bold text-zinc-900">
        What we detected
      </h2>
      <p className="mt-bw-1 text-bw-sm text-zinc-600">
        Every ingredient call carries a confidence level and a source. Spot something wrong?
        Use &ldquo;Suggest a fix&rdquo; below.
      </p>

      {ingredients.length === 0 && tags.length === 0 ? (
        <p className="mt-bw-3 text-bw-sm italic text-zinc-500">
          No ingredient data recorded for this dish yet.
        </p>
      ) : (
        <>
          {ingredients.length > 0 && (
            <ul className="mt-bw-3 flex flex-wrap gap-bw-2" data-testid="detected-ingredients">
              {ingredients.map((row) => (
                <li key={row.slug ?? row.name ?? 'unknown'}>
                  <AssociationChip row={row} allergen={row.allergen} />
                </li>
              ))}
            </ul>
          )}
          {tags.length > 0 && (
            <ul className="mt-bw-2 flex flex-wrap gap-bw-2" data-testid="detected-tags">
              {tags.map((row) => (
                <li key={row.slug ?? row.name ?? 'unknown'}>
                  <AssociationChip row={row} />
                </li>
              ))}
            </ul>
          )}
          <p className="mt-bw-3 text-bw-xs text-zinc-500">
            ✓ confirmed — a human verified it · ~ suggested — extracted, awaiting review · ≈
            inferred — derived from other data
          </p>
        </>
      )}
    </section>
  );
}

function AssociationChip({ row, allergen = false }: { row: DetectedAssociation; allergen?: boolean }) {
  const label = row.name ?? row.slug ?? 'Unknown';
  return (
    <span
      title={`${CONFIDENCE_GLOSS[row.confidence]} · source: ${row.source}`}
      className={[
        'inline-flex items-center gap-bw-1 rounded-bw-pill border px-bw-2 py-bw-0_5 text-bw-xs font-semibold',
        allergen
          ? 'border-bite bg-bite-light text-bite-dark'
          : 'border-zinc-200 bg-zinc-50 text-zinc-700',
      ].join(' ')}
    >
      {label}
      <span aria-label={`${row.confidence} — ${CONFIDENCE_GLOSS[row.confidence]}`} className="font-normal opacity-70">
        {CONFIDENCE_MARK[row.confidence]}
      </span>
    </span>
  );
}
