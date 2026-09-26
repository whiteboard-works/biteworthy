import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { FilterControls, UnconfirmedStrictNotice } from '../FilterControls';
import type { FilterSummary } from '../../../../lib/restaurants';

vi.mock('../../../_PostHogProvider', () => ({
  useTracker: () => ({ track: vi.fn() }),
}));

/**
 * Strict mode's confidence gate can hide most of a menu when the
 * restaurant's ingredients just haven't been confirmed yet — that
 * looks like a broken page unless the count says otherwise. These
 * pin the honesty line to strict mode only, and to the unconfirmed
 * count specifically (not the total hidden count, which already has
 * its own line elsewhere on the page).
 */
describe('UnconfirmedStrictNotice', () => {
  it('renders nothing at zero', () => {
    render(<UnconfirmedStrictNotice count={0} />);
    expect(screen.queryByTestId('unconfirmed-strict-notice')).not.toBeInTheDocument();
  });

  it('singularizes at one', () => {
    render(<UnconfirmedStrictNotice count={1} />);
    expect(screen.getByTestId('unconfirmed-strict-notice')).toHaveTextContent(
      '1 dish hidden because nobody has confirmed its ingredients yet.',
    );
  });

  it('pluralizes above one', () => {
    render(<UnconfirmedStrictNotice count={4} />);
    expect(screen.getByTestId('unconfirmed-strict-notice')).toHaveTextContent(
      '4 dishes hidden because nobody has confirmed their ingredients yet.',
    );
  });
});

describe('FilterControls — strict-mode unconfirmed line', () => {
  const summary = (strictness: FilterSummary['strictness']): FilterSummary => ({
    source: 'none',
    preset_slug: null,
    strictness,
    avoid_ingredient_ids: [],
    avoid_tag_ids: [],
  });

  it('shows the unconfirmed count only when the active strictness is strict', () => {
    render(
      <FilterControls
        filter={summary('balanced')}
        strictnessOverride="strict"
        isPending={false}
        slug="chamayo"
        unconfirmedStrictCount={3}
        onStrictnessChange={vi.fn()}
      />,
    );
    expect(screen.getByTestId('unconfirmed-strict-notice')).toBeInTheDocument();
  });

  it('hides the line outside strict mode even with a nonzero count', () => {
    render(
      <FilterControls
        filter={summary('balanced')}
        strictnessOverride={null}
        isPending={false}
        slug="chamayo"
        unconfirmedStrictCount={3}
        onStrictnessChange={vi.fn()}
      />,
    );
    expect(screen.queryByTestId('unconfirmed-strict-notice')).not.toBeInTheDocument();
  });

  it('falls back to the server filter strictness when no override is active yet', () => {
    render(
      <FilterControls
        filter={summary('strict')}
        strictnessOverride={null}
        isPending={false}
        slug="chamayo"
        unconfirmedStrictCount={2}
        onStrictnessChange={vi.fn()}
      />,
    );
    expect(screen.getByTestId('unconfirmed-strict-notice')).toBeInTheDocument();
  });
});
