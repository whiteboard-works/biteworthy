import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import DetectedIngredients from '../_DetectedIngredients';
import type { DetectedAssociation, DetectedIngredient } from '../../../../../../lib/restaurants';

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
    const basilChip = screen.getByTitle('confirmed — a human verified it · source: human');
    expect(basilChip).toHaveTextContent('Basil');
    expect(basilChip).not.toHaveTextContent('AI');
    expect(screen.getByTestId('detected-tags')).toHaveTextContent('Contains gluten');
  });

  it('emphasizes allergen ingredients over non-allergens', () => {
    render(<DetectedIngredients ingredients={[wheat, basil]} tags={[]} />);

    const wheatChip = screen.getByTitle('inferred — derived from other data · source: ai');
    const basilChip = screen.getByTitle('confirmed — a human verified it · source: human');
    expect(wheatChip.className).toContain('border-bite');
    expect(basilChip.className).not.toContain('border-bite');
  });

  it('says so when no data is recorded rather than rendering nothing', () => {
    render(<DetectedIngredients ingredients={[]} tags={[]} />);
    expect(screen.getByText(/no ingredient data recorded/i)).toBeInTheDocument();
  });
});
