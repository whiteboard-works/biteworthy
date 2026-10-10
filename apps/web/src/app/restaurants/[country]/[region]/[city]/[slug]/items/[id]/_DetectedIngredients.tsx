import type {
  DetectedAssociation,
  DetectedIngredient,
} from '../../../../../../../../lib/restaurants';

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

// The mark alone says a person checked; only a non-human source earns a
// visible word, so a chip never reads "✓ human". A source missing here
// shows no word (a `??` fallback once leaked the raw source name).
const SOURCE_WORD: Partial<Record<DetectedAssociation['source'], string>> = {
  ai: 'AI',
  derived: 'inferred',
  ingredient_derived: 'inferred',
  owner: 'owner',
};

const LEGEND_ID = 'detected-legend';

export default function DetectedIngredients({
  ingredients,
  tags,
}: {
  ingredients: DetectedIngredient[];
  tags: DetectedAssociation[];
}) {
  return (
    <section aria-labelledby="detected-heading" className="mt-bw-8">
      <div className="flex flex-wrap items-baseline gap-x-bw-3 gap-y-bw-1">
        <h2 id="detected-heading" className="text-bw-lg font-bold text-zinc-900">
          What we detected
        </h2>
        <button
          type="button"
          popoverTarget={LEGEND_ID}
          className="text-bw-sm font-semibold text-bite hover:text-bite-dark"
        >
          What the marks mean
        </button>
      </div>
      <p className="mt-bw-1 text-bw-sm text-zinc-600">
        Spot something wrong? Use &ldquo;Suggest a fix&rdquo; below.
      </p>

      {/* Native popover: top layer, centered, closes on Escape or an outside click, no client JS. */}
      <div
        id={LEGEND_ID}
        popover="auto"
        data-testid="detected-legend"
        className="m-auto w-[min(92vw,24rem)] rounded-bw-lg border border-zinc-200 bg-white p-bw-4 text-bw-sm text-zinc-700 shadow-xl"
      >
        <p className="font-semibold text-zinc-900">
          Every ingredient call carries a confidence level and a source.
        </p>
        <ul className="mt-bw-3 space-y-bw-2">
          <li>
            <span className="font-semibold text-zinc-900">✓ confirmed</span> — a human verified it
          </li>
          <li>
            <span className="font-semibold text-zinc-900">~ suggested</span> — extracted, awaiting
            review
          </li>
          <li>
            <span className="font-semibold text-zinc-900">≈ inferred</span> — derived from other
            data
          </li>
          <li>
            <span className="font-semibold text-zinc-900">AI</span> — came from the menu reader, not
            a person
          </li>
          <li>
            <span className="font-semibold text-zinc-900">inferred</span>, after a mark — worked out
            from the dish&rsquo;s other ingredients
          </li>
        </ul>
        <button
          type="button"
          popoverTarget={LEGEND_ID}
          popoverTargetAction="hide"
          className="mt-bw-4 text-bw-sm font-semibold text-bite hover:text-bite-dark"
        >
          Close
        </button>
      </div>

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
        </>
      )}
    </section>
  );
}

function AssociationChip({
  row,
  allergen = false,
}: {
  row: DetectedAssociation;
  allergen?: boolean;
}) {
  const label = row.name ?? row.slug ?? 'Unknown';
  // `source` must be perceivable without hover — touch screens and
  // screen readers never see a title tooltip. Non-human sources get a
  // visible word; the aria-label always carries the full provenance.
  const sourceWord = SOURCE_WORD[row.source];
  const provenance = `${row.confidence} — ${CONFIDENCE_GLOSS[row.confidence]} · source: ${row.source}`;
  return (
    <span
      title={provenance}
      className={[
        'inline-flex items-center gap-bw-1 rounded-bw-pill border px-bw-2 py-bw-0_5 text-bw-xs font-semibold',
        allergen
          ? 'border-bite bg-bite-light text-bite-dark'
          : 'border-zinc-200 bg-zinc-50 text-zinc-700',
      ].join(' ')}
    >
      {label}
      <span aria-label={provenance} className="font-normal opacity-70">
        {CONFIDENCE_MARK[row.confidence]}
        {sourceWord && ` ${sourceWord}`}
      </span>
    </span>
  );
}
