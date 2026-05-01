import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { HiddenReasonChip, StrictnessToggle } from '../RestaurantClient';

/**
 * Phase post-5 — first JSX render tests for the web app.
 *
 * Targets the already-exported helpers (HiddenReasonChip,
 * StrictnessToggle) to prove the test infra works end-to-end.
 *
 * The Phase 4.11.4 ItemRow photo_url contract isn't covered here —
 * ItemRow is a file-private component inside RestaurantClient, and
 * extracting it is a separate scoped follow-up. The infra wiring
 * has to land first; once it does, that follow-up is a small one
 * (~10 lines of render-test code).
 */

describe('HiddenReasonChip', () => {
  it('renders the avoid_ingredient label with name + family', () => {
    render(
      <HiddenReasonChip
        reason={{
          kind: 'avoid_ingredient',
          ingredient_id: 'ing-1',
          ingredient_name: 'Cheddar',
          ingredient_family: 'dairy',
        }}
      />,
    );
    expect(screen.getByTestId('chip-avoid_ingredient')).toBeInTheDocument();
    expect(screen.getByTestId('chip-avoid_ingredient')).toHaveTextContent('Contains dairy (Cheddar)');
  });

  it('renders the avoid_tag label with name + family', () => {
    render(
      <HiddenReasonChip
        reason={{
          kind: 'avoid_tag',
          tag_id: 'tag-1',
          tag_name: 'Contains Dairy',
          tag_family: 'allergen',
        }}
      />,
    );
    expect(screen.getByTestId('chip-avoid_tag')).toHaveTextContent('Tagged allergen: Contains Dairy');
  });

  it('renders the unconfirmed_strict label with the confidence value', () => {
    render(
      <HiddenReasonChip
        reason={{ kind: 'unconfirmed_strict', confidence: 'inferred' }}
      />,
    );
    expect(screen.getByTestId('chip-unconfirmed_strict')).toHaveTextContent('inferred');
  });
});

describe('StrictnessToggle', () => {
  it('renders all three strictness modes with the active one pressed', () => {
    render(
      <StrictnessToggle active="balanced" loading={false} onChange={() => {}} />,
    );
    const buttons = screen.getAllByRole('button');
    expect(buttons).toHaveLength(3);
    const balanced = buttons.find((b) => b.textContent === 'Balanced');
    expect(balanced).toBeDefined();
    expect(balanced).toHaveAttribute('aria-pressed', 'true');
    const strict = buttons.find((b) => b.textContent === 'Strict');
    expect(strict).toHaveAttribute('aria-pressed', 'false');
  });

  it('disables every button + shows "refreshing…" while loading', () => {
    render(
      <StrictnessToggle active="strict" loading={true} onChange={() => {}} />,
    );
    screen.getAllByRole('button').forEach((b) => {
      expect(b).toBeDisabled();
    });
    expect(screen.getByText(/refreshing/i)).toBeInTheDocument();
  });

  it('fires onChange when an inactive button is clicked, not when the active one is clicked', async () => {
    const onChange = vi.fn();
    render(
      <StrictnessToggle active="balanced" loading={false} onChange={onChange} />,
    );

    screen.getByText('Strict').click();
    expect(onChange).toHaveBeenCalledWith('strict');

    screen.getByText('Balanced').click();
    // Active button doesn't re-fire — the handler short-circuits.
    expect(onChange).toHaveBeenCalledTimes(1);
  });
});
