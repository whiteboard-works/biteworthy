import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import {
  AllergenNotice,
  FilterBadge,
  HiddenReasonChip,
  ShareLinkButton,
  ShareTokenNotice,
  StrictnessToggle,
} from '../RestaurantClient';

vi.mock('../../../_PostHogProvider', () => ({
  useTracker: () => ({ track: vi.fn() }),
}));
import type { FilterSummary } from '../../../../lib/restaurants';

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

describe('FilterBadge', () => {
  const summary = (source: FilterSummary['source']): FilterSummary => ({
    source,
    preset_slug: source === 'preset' ? 'vegan' : null,
    strictness: 'balanced',
    avoid_ingredient_ids: [],
    avoid_tag_ids: [],
  });

  it.each([
    ['preset', 'Preset · vegan'],
    ['user_profile', 'Your saved profile'],
    // A share-link recipient has the sender's filter applied — the badge
    // must never present that menu as unfiltered.
    ['profile_token', 'Shared filter'],
    ['none', 'No filter'],
  ] as const)('labels source %s as "%s"', (source, label) => {
    render(<FilterBadge filter={summary(source)} />);
    expect(screen.getByTestId('filter-badge')).toHaveTextContent(`${label} · balanced`);
  });
});

describe('ShareTokenNotice', () => {
  const summary = (source: FilterSummary['source']): FilterSummary => ({
    source,
    preset_slug: source === 'preset' ? 'celiac' : null,
    strictness: 'balanced',
    avoid_ingredient_ids: [],
    avoid_tag_ids: [],
  });

  // A refused share token used to render a bare 404. The recipient
  // believes they're looking at the sender's filtered view — the notice
  // must say what the menu actually shows now.
  it('says unfiltered when nothing else applies', () => {
    render(<ShareTokenNotice filter={summary('none')} />);
    const notice = screen.getByTestId('share-token-notice');
    expect(notice).toHaveTextContent(/invalid or has expired/i);
    expect(notice).toHaveTextContent(/unfiltered/i);
  });

  it('names the fallback filter instead of falsely claiming unfiltered', () => {
    render(<ShareTokenNotice filter={summary('user_profile')} />);
    const notice = screen.getByTestId('share-token-notice');
    expect(notice).toHaveTextContent(/Your saved profile/);
    expect(notice).not.toHaveTextContent(/unfiltered/i);
  });
});

describe('AllergenNotice', () => {
  // Legal remediation E1 — the point-of-use disclaimer must be present
  // and non-dismissable on every filtered menu, and must name the
  // false-negative case (a result can still miss an allergen).
  it('renders the disclaimer with no dismiss control', () => {
    render(<AllergenNotice />);
    const notice = screen.getByTestId('allergen-notice');
    expect(notice).toHaveTextContent(/not a guarantee/i);
    expect(notice).toHaveTextContent(/miss an allergen/i);
    expect(notice).toHaveTextContent(/confirm with the restaurant/i);
    // Non-dismissable: no button inside the notice to close it.
    expect(notice.querySelector('button')).toBeNull();
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

describe('ShareLinkButton', () => {
  const summary = (source: FilterSummary['source']): FilterSummary => ({
    source,
    preset_slug: source === 'preset' ? 'celiac' : null,
    strictness: 'balanced',
    avoid_ingredient_ids: [],
    avoid_tag_ids: [],
  });

  function clickAndGetCopiedUrl(source: FilterSummary['source']): Promise<string> {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    render(<ShareLinkButton slug="chamayo" filter={summary(source)} />);
    screen.getByTestId('share-link').click();
    return vi.waitFor(() => {
      expect(writeText).toHaveBeenCalled();
      return writeText.mock.calls[0]![0] as string;
    });
  }

  it('shares the bare URL when no filter applies — an empty-list token is VALID to the API and would label an unfiltered menu "Shared filter"', async () => {
    const url = await clickAndGetCopiedUrl('none');
    expect(url).toBe(`${window.location.origin}/r/chamayo`);
  });

  it('shares a preset as its slug, not a pre-expanded token', async () => {
    const url = await clickAndGetCopiedUrl('preset');
    expect(url).toBe(`${window.location.origin}/r/chamayo?profile=celiac`);
  });

  it('shares a saved profile as an encoded token', async () => {
    const url = await clickAndGetCopiedUrl('user_profile');
    expect(url).toContain('/r/chamayo?p=');
  });
});
