import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import DetectedIngredients from '../_DetectedIngredients';
import type {
  DetectedAssociation,
  DetectedIngredient,
} from '../../../../../../../../../lib/restaurants';

// The panel is the honest-disclosure surface: provenance must render
// verbatim, so a "confirmed by a human" call and an "AI inferred" call
// are visually distinct — and an allergen ingredient stands out.
describe('DetectedIngredients', () => {
  const wheat: DetectedIngredient = {
    slug: 'grain-wheat',
    name: 'Wheat',
    confidence: 'inferred',
    source: 'ai',
    allergen: true,
  };
  const basil: DetectedIngredient = {
    slug: 'herb-basil',
    name: 'Basil',
    confidence: 'confirmed',
    source: 'human',
    allergen: false,
  };
  const glutenTag: DetectedAssociation = {
    slug: 'contains-gluten',
    name: 'Contains gluten',
    confidence: 'suggested',
    source: 'human',
  };

  it('renders each association with its confidence gloss and source', () => {
    render(<DetectedIngredients ingredients={[wheat, basil]} tags={[glutenTag]} />);

    const wheatChip = screen.getByTitle('inferred — derived from other data · source: ai');
    expect(wheatChip).toHaveTextContent('Wheat');
    // Source must be perceivable without hover: AI-sourced chips carry a
    // visible marker, and the aria-label repeats the full provenance.
    expect(wheatChip).toHaveTextContent('AI');
    // A human-sourced chip is the mark alone: "✓ human" on every chip
    // was noise (a `??` fallback once leaked the raw source name).
    const basilChip = screen.getByTitle('confirmed — a human verified it · source: human');
    expect(basilChip).toHaveTextContent(/^Basil\s*✓$/);
    expect(screen.getByTestId('detected-tags')).toHaveTextContent(/^Contains gluten\s*~$/);
  });

  it('keeps the legend in a popover list rather than a paragraph under the chips', () => {
    render(<DetectedIngredients ingredients={[wheat, basil]} tags={[glutenTag]} />);

    const legend = screen.getByTestId('detected-legend');
    expect(legend).toHaveAttribute('popover', 'auto');
    const trigger = screen.getByRole('button', { name: /what the marks mean/i });
    expect(trigger).toHaveAttribute('popovertarget', legend.id);
    const items = legend.querySelectorAll('li');
    expect(items.length).toBeGreaterThanOrEqual(3);
    expect(items[0]).toHaveTextContent('✓ confirmed — a human verified it');
    // The old inline paragraph is gone from the section body.
    expect(screen.queryByText(/chips marked ai/i)).not.toBeInTheDocument();
  });

  it('emphasizes allergen ingredients over non-allergens', () => {
    render(<DetectedIngredients ingredients={[wheat, basil]} tags={[]} />);

    const wheatChip = screen.getByTitle('inferred — derived from other data · source: ai');
    const basilChip = screen.getByTitle('confirmed — a human verified it · source: human');
    expect(wheatChip.className).toContain('border-bite');
    expect(basilChip.className).not.toContain('border-bite');
  });

  it('labels inferred, AI, and derived rows so they do not look human-verified', () => {
    const derivedWheat: DetectedIngredient = {
      slug: 'grain-wheat',
      name: 'Wheat',
      confidence: 'suggested',
      source: 'derived',
      allergen: true,
    };
    const inferredGluten: DetectedAssociation = {
      slug: 'contains-gluten',
      name: 'Contains gluten',
      confidence: 'suggested',
      source: 'ingredient_derived',
    };

    render(<DetectedIngredients ingredients={[derivedWheat]} tags={[inferredGluten]} />);

    const wheatChip = screen.getByTitle('suggested — extracted, awaiting review · source: derived');
    expect(wheatChip).toHaveTextContent('inferred');
    const glutenChip = screen.getByTitle(
      'suggested — extracted, awaiting review · source: ingredient_derived',
    );
    expect(glutenChip).toHaveTextContent('inferred');
  });

  it('says so when no data is recorded rather than rendering nothing', () => {
    render(<DetectedIngredients ingredients={[]} tags={[]} />);
    expect(screen.getByText(/no ingredient data recorded/i)).toBeInTheDocument();
    // No chips, so nothing for a legend to explain.
    expect(screen.queryByRole('button', { name: /what the marks mean/i })).not.toBeInTheDocument();
  });
});
