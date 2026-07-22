import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ProfilePayload } from '../../../../lib/profile';
import { OPT_OUT_KEY } from '../../../../lib/track';

/**
 * The account page shows every dietary preference and edits it in place
 * (plus the legal-remediation E7a analytics opt-out that already lived
 * here). The load-bearing correctness property: because the profile
 * PATCH replaces each array it receives wholesale, an edit must submit
 * the full remaining set — removing one avoid ingredient must send the
 * OTHER ids, never an empty/partial array that silently wipes the
 * safety filter.
 */

const mockReplace = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
}));

const mockFetchProfile = vi.fn();
const mockUpdateProfile = vi.fn();
vi.mock('../../../../lib/profile', () => {
  // Defined inside the hoisted factory — a top-level class can't be
  // referenced here (only `mock`-prefixed vars are hoist-exempt).
  class NotSignedInError extends Error {}
  return {
    fetchProfile: (...a: unknown[]) => mockFetchProfile(...a),
    updateProfile: (...a: unknown[]) => mockUpdateProfile(...a),
    NotSignedInError,
  };
});
import { NotSignedInError } from '../../../../lib/profile';

const mockFetchDietaryProfiles = vi.fn();
const mockSearchIngredients = vi.fn();
vi.mock('../../../../lib/onboarding', () => ({
  fetchDietaryProfiles: (...a: unknown[]) => mockFetchDietaryProfiles(...a),
  searchIngredients: (...a: unknown[]) => mockSearchIngredients(...a),
}));

import ProfileSettingsPage from '../page';

const PROFILE: ProfilePayload = {
  avoid_ingredient_ids: ['ing-cheese', 'ing-wheat'],
  avoid_tag_ids: ['tag-fried'],
  prefer_tag_ids: [],
  liked_ingredient_ids: [],
  liked_tag_ids: ['tag-thai'],
  disliked_ingredient_ids: [],
  disliked_tag_ids: [],
  avoid_ingredients: [
    { id: 'ing-cheese', slug: 'dairy-cheese', name: 'Cheese' },
    { id: 'ing-wheat', slug: 'wheat', name: 'Wheat' },
  ],
  avoid_tags: [{ id: 'tag-fried', slug: 'prep-fried', name: 'Fried', family: 'prep' }],
  prefer_tags: [],
  liked_ingredients: [],
  liked_tags: [{ id: 'tag-thai', slug: 'cuisine-thai', name: 'Thai', family: 'cuisine' }],
  disliked_ingredients: [],
  disliked_tags: [],
  strictness: 'balanced',
  primary_dietary_profile: { id: 'dp-vegan', slug: 'vegan', name: 'Vegan' },
  disclaimer_acknowledged_at: '2026-07-01T00:00:00Z',
};

beforeEach(() => {
  localStorage.clear();
  mockReplace.mockReset();
  mockFetchProfile.mockReset().mockResolvedValue(structuredClone(PROFILE));
  mockUpdateProfile.mockReset().mockResolvedValue(structuredClone(PROFILE));
  mockFetchDietaryProfiles.mockReset().mockResolvedValue([
    { slug: 'vegan', name: 'Vegan', description: 'No animal products' },
    { slug: 'keto', name: 'Keto', description: 'Low carb' },
  ]);
  mockSearchIngredients.mockReset().mockResolvedValue([]);
});

afterEach(() => localStorage.clear());

describe('ProfileSettingsPage — dietary preferences', () => {
  it('renders the current preferences with resolved names', async () => {
    render(<ProfileSettingsPage />);

    // Avoid ingredients by NAME (not UUID), preset, strictness, taste.
    expect(await screen.findByText('Cheese')).toBeInTheDocument();
    expect(screen.getByText('Wheat')).toBeInTheDocument();
    expect(screen.getByTestId('pref-avoid-tags')).toHaveTextContent('Fried');
    expect(screen.getByTestId('pref-preset')).toHaveTextContent('Vegan');
    expect(screen.getByTestId('pref-taste')).toHaveTextContent('Thai');
    expect(screen.getByTestId('set-strictness-balanced')).toHaveAttribute('aria-pressed', 'true');
  });

  it('changes strictness via a partial patch', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('set-strictness-strict'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({ strictness: 'strict' }),
    );
  });

  it('removing an avoid ingredient sends the REMAINING ids (never wipes the list)', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('remove-avoid-ingredient-dairy-cheese'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({ avoid_ingredient_ids: ['ing-wheat'] }),
    );
  });

  it('removing an avoid tag sends the remaining tag ids', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('remove-avoid-tag-prep-fried'));

    await waitFor(() => expect(mockUpdateProfile).toHaveBeenCalledWith({ avoid_tag_ids: [] }));
  });

  it('applies a dietary preset additively by slug', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('preset-toggle'));
    fireEvent.click(await screen.findByTestId('apply-preset-keto'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({ dietary_profile_slug: 'keto' }),
    );
  });

  it('adds a searched ingredient onto the existing avoid list', async () => {
    mockSearchIngredients.mockResolvedValue([
      { id: 'ing-peanut', slug: 'peanut', name: 'Peanut', path: 'peanut', aliases: [], allergen: true },
    ]);
    render(<ProfileSettingsPage />);
    fireEvent.change(await screen.findByLabelText('avoid-ingredient-search'), {
      target: { value: 'peanut' },
    });

    fireEvent.click(await screen.findByTestId('add-avoid-ingredient-peanut'));
    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({
        avoid_ingredient_ids: ['ing-cheese', 'ing-wheat', 'ing-peanut'],
      }),
    );
  });

  it('redirects to /login when the profile load is unauthenticated', async () => {
    mockFetchProfile.mockRejectedValue(new NotSignedInError());
    render(<ProfileSettingsPage />);

    await waitFor(() =>
      expect(mockReplace).toHaveBeenCalledWith('/login?next=%2Fprofile%2Fsettings'),
    );
  });
});

/**
 * Legal remediation E7a — the analytics opt-out toggle must read + write
 * the same localStorage flag buildWebTracker honors. (Pre-existing
 * behavior; unchanged by the preferences work.)
 */
describe('ProfileSettingsPage — analytics toggle', () => {
  it('defaults to analytics-on (no opt-out flag set)', async () => {
    render(<ProfileSettingsPage />);
    const toggle = (await screen.findByLabelText('analytics-opt-in')) as HTMLInputElement;
    expect(toggle.checked).toBe(true);
    expect(localStorage.getItem(OPT_OUT_KEY)).toBeNull();
  });

  it('writes the opt-out flag when toggled off, and clears it when toggled back on', async () => {
    render(<ProfileSettingsPage />);
    const toggle = (await screen.findByLabelText('analytics-opt-in')) as HTMLInputElement;

    fireEvent.click(toggle); // turn analytics OFF
    await waitFor(() => expect(localStorage.getItem(OPT_OUT_KEY)).toBe('1'));
    expect(screen.getByTestId('analytics-state')).toHaveTextContent(/opted out/i);

    fireEvent.click(screen.getByLabelText('analytics-opt-in')); // back ON
    await waitFor(() => expect(localStorage.getItem(OPT_OUT_KEY)).toBeNull());
  });

  it('reflects a pre-existing opt-out on load', async () => {
    localStorage.setItem(OPT_OUT_KEY, '1');
    render(<ProfileSettingsPage />);
    const toggle = (await screen.findByLabelText('analytics-opt-in')) as HTMLInputElement;
    expect(toggle.checked).toBe(false);
  });
});
