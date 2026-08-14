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
// Stable router object — the real useRouter is referentially stable, so a
// fresh object per render would spuriously re-fire the [router]-dep effects.
const mockRouter = { replace: mockReplace };
vi.mock('next/navigation', () => ({
  useRouter: () => mockRouter,
}));

const mockFetchProfile = vi.fn();
const mockUpdateProfile = vi.fn();
const mockFetchMyReviews = vi.fn();
const mockFetchMyFavorites = vi.fn();
vi.mock('../../../../lib/profile', () => {
  // Defined inside the hoisted factory — a top-level class can't be
  // referenced here (only `mock`-prefixed vars are hoist-exempt).
  class NotSignedInError extends Error {}
  return {
    fetchProfile: (...a: unknown[]) => mockFetchProfile(...a),
    updateProfile: (...a: unknown[]) => mockUpdateProfile(...a),
    fetchMyReviews: (...a: unknown[]) => mockFetchMyReviews(...a),
    fetchMyFavorites: (...a: unknown[]) => mockFetchMyFavorites(...a),
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

const mockListTokens = vi.fn();
const mockCreateToken = vi.fn();
const mockRevokeToken = vi.fn();
vi.mock('../../../../lib/mcp-tokens', () => ({
  listTokens: (...a: unknown[]) => mockListTokens(...a),
  createToken: (...a: unknown[]) => mockCreateToken(...a),
  revokeToken: (...a: unknown[]) => mockRevokeToken(...a),
}));

import ProfileSettingsPage from '../page';

const PROFILE: ProfilePayload = {
  avoid_ingredient_ids: ['ing-cheese', 'ing-wheat'],
  avoid_tag_ids: ['tag-fried'],
  prefer_tag_ids: [],
  liked_ingredient_ids: ['ing-basil'],
  liked_tag_ids: ['tag-thai'],
  disliked_ingredient_ids: [],
  disliked_tag_ids: [],
  avoid_ingredients: [
    { id: 'ing-cheese', slug: 'dairy-cheese', name: 'Cheese' },
    { id: 'ing-wheat', slug: 'wheat', name: 'Wheat' },
  ],
  avoid_tags: [{ id: 'tag-fried', slug: 'prep-fried', name: 'Fried', family: 'prep' }],
  liked_ingredients: [{ id: 'ing-basil', slug: 'herb-basil', name: 'Basil' }],
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
  mockFetchMyReviews.mockReset().mockResolvedValue({ reviews: [], total: 0 });
  mockFetchMyFavorites.mockReset().mockResolvedValue({ restaurants: [], items: [] });
  mockListTokens.mockReset().mockResolvedValue({
    tokens: [],
    scopes: ['discovery:read', 'profile:write'],
    full_access_scope: '*',
  });
  mockCreateToken.mockReset().mockResolvedValue({
    id: 't-1', name: 'Claude Code', scopes: ['discovery:read'], secret: 'bw_mcp_x',
    created_at: '2026-08-14T00:00:00Z', last_used_at: null,
  });
  mockRevokeToken.mockReset().mockResolvedValue(undefined);
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
    // Taste shows both tag (Thai) and ingredient (Basil) love signals.
    expect(screen.getByTestId('pref-taste')).toHaveTextContent('Thai');
    expect(screen.getByTestId('pref-taste')).toHaveTextContent('Basil');
    expect(screen.getByTestId('set-strictness-balanced')).toHaveAttribute('aria-pressed', 'true');
  });

  it('changes strictness via a partial patch', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('set-strictness-strict'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({ strictness: 'strict' }),
    );
  });

  // Sends the one change, never a rebuilt array. This page holds a profile
  // loaded at mount, and the chat or a connected app can add an allergen in
  // the meantime — a wholesale write would silently revert it, which is the
  // one bug on this screen that can put someone in front of a dish that
  // hurts them.
  it('removing an avoid ingredient sends only that removal', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('remove-avoid-ingredient-dairy-cheese'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({
        remove_avoid_ingredient_ids: ['ing-cheese'],
      }),
    );
  });

  it('never sends a rebuilt avoid array, which would revert a concurrent add', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('remove-avoid-ingredient-dairy-cheese'));

    await waitFor(() => expect(mockUpdateProfile).toHaveBeenCalled());
    expect(mockUpdateProfile.mock.calls[0]?.[0]).not.toHaveProperty('avoid_ingredient_ids');
  });

  it('removing an avoid tag sends only that removal', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('remove-avoid-tag-prep-fried'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({ remove_avoid_tag_ids: ['tag-fried'] }),
    );
  });

  it('applies a dietary preset additively by slug', async () => {
    render(<ProfileSettingsPage />);
    fireEvent.click(await screen.findByTestId('preset-toggle'));
    fireEvent.click(await screen.findByTestId('apply-preset-keto'));

    await waitFor(() =>
      expect(mockUpdateProfile).toHaveBeenCalledWith({ dietary_profile_slug: 'keto' }),
    );
  });

  it('adds a searched ingredient as an addition, not a replacement', async () => {
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
        add_avoid_ingredient_ids: ['ing-peanut'],
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

describe('ProfileSettingsPage — favorites', () => {
  it('shows an empty state when nothing is saved', async () => {
    render(<ProfileSettingsPage />);
    expect(await screen.findByTestId('favorites-empty')).toBeInTheDocument();
  });

  it('lists saved restaurants and dishes, linking published ones', async () => {
    mockFetchMyFavorites.mockResolvedValue({
      restaurants: [{ id: 'r1', slug: 'ninis', name: 'Ninis', status: 'published' }],
      items: [
        {
          id: 'i1',
          name: 'Carne Asada Taco',
          status: 'published',
          restaurant: { id: 'r1', slug: 'ninis', name: 'Ninis', status: 'published' },
        },
        {
          id: 'i2',
          name: 'Gone Dish',
          status: 'removed',
          restaurant: { id: 'r1', slug: 'ninis', name: 'Ninis', status: 'published' },
        },
        {
          // Published dish, but its restaurant is closed → still must not link.
          id: 'i3',
          name: 'Orphan Dish',
          status: 'published',
          restaurant: { id: 'r2', slug: 'closed-spot', name: 'Closed Spot', status: 'closed' },
        },
      ],
    });
    render(<ProfileSettingsPage />);

    const rest = await screen.findByTestId('favorite-restaurant-r1');
    expect(rest.querySelector('a')).toHaveAttribute('href', '/restaurants/ninis');

    const dish = screen.getByTestId('favorite-dish-i1');
    expect(dish.querySelector('a')).toHaveAttribute('href', '/restaurants/ninis/items/i1');

    // A removed dish is shown but not linked.
    const gone = screen.getByTestId('favorite-dish-i2');
    expect(gone.querySelector('a')).toBeNull();
    expect(gone).toHaveTextContent(/no longer available/i);

    // A published dish at an unpublished restaurant must not link either.
    const orphan = screen.getByTestId('favorite-dish-i3');
    expect(orphan.querySelector('a')).toBeNull();
  });
});

describe('ProfileSettingsPage — my reviews', () => {
  it('shows an empty state when the user has no reviews', async () => {
    render(<ProfileSettingsPage />);
    expect(await screen.findByTestId('my-reviews-empty')).toBeInTheDocument();
  });

  it('lists the user reviews with restaurant/item context and a hidden badge', async () => {
    mockFetchMyReviews.mockResolvedValue({
      total: 2,
      reviews: [
        {
          id: 'rev-1',
          item: {
            id: 'item-1',
            name: 'Carne Asada Taco',
            status: 'published',
            restaurant: { id: 'r1', slug: 'ninis', name: 'Ninis' },
          },
          rating: 5,
          body: 'Best in town.',
          photo_url: null,
          hidden: false,
          hidden_reason: null,
          created_at: '2026-07-01T00:00:00Z',
          updated_at: '2026-07-01T00:00:00Z',
        },
        {
          id: 'rev-2',
          item: {
            id: 'item-2',
            name: 'Bean Burrito',
            status: 'published',
            restaurant: { id: 'r1', slug: 'ninis', name: 'Ninis' },
          },
          rating: 2,
          body: 'spammy',
          photo_url: null,
          hidden: true,
          hidden_reason: 'spam',
          created_at: '2026-06-01T00:00:00Z',
          updated_at: '2026-06-01T00:00:00Z',
        },
      ],
    });
    render(<ProfileSettingsPage />);

    const first = await screen.findByTestId('my-review-rev-1');
    expect(first).toHaveTextContent('Carne Asada Taco');
    expect(first.querySelector('a')).toHaveAttribute('href', '/restaurants/ninis/items/item-1');
    // The hidden review tells the author why it's hidden.
    expect(screen.getByTestId('my-review-hidden-rev-2')).toHaveTextContent(/spam/i);
  });

  it('renders a removed dish as plain text (no dead link) with a note', async () => {
    mockFetchMyReviews.mockResolvedValue({
      total: 1,
      reviews: [
        {
          id: 'rev-x',
          item: {
            id: 'item-x',
            name: 'Old Taco',
            status: 'removed',
            restaurant: { id: 'r1', slug: 'ninis', name: 'Ninis' },
          },
          rating: 3,
          body: null,
          photo_url: null,
          hidden: false,
          hidden_reason: null,
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z',
        },
      ],
    });
    render(<ProfileSettingsPage />);

    const row = await screen.findByTestId('my-review-rev-x');
    expect(row.querySelector('a')).toBeNull(); // no dead link to a 404
    expect(row).toHaveTextContent('Old Taco');
    expect(row).toHaveTextContent(/no longer on the menu/i);
  });

  it('paginates: a Show more control loads the next page and shows the total', async () => {
    const mk = (id: string) => ({
      id,
      item: {
        id: `i-${id}`,
        name: `Dish ${id}`,
        status: 'published',
        restaurant: { id: 'r1', slug: 'ninis', name: 'Ninis' },
      },
      rating: 4,
      body: null,
      photo_url: null,
      hidden: false,
      hidden_reason: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
    });
    mockFetchMyReviews
      .mockResolvedValueOnce({ reviews: [mk('a')], total: 3 })
      .mockResolvedValueOnce({ reviews: [mk('b'), mk('c')], total: 3 });
    render(<ProfileSettingsPage />);

    const more = await screen.findByTestId('my-reviews-load-more');
    expect(more).toHaveTextContent('Show more (2)');
    expect(screen.getByTestId('my-reviews').querySelector('h2')).toHaveTextContent('My reviews (3)');

    fireEvent.click(more);
    await waitFor(() => expect(screen.getByTestId('my-review-c')).toBeInTheDocument());
    // All three loaded → the control is gone.
    expect(screen.queryByTestId('my-reviews-load-more')).toBeNull();
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

/**
 * Access tokens for MCP clients.
 *
 * A token used to get full access by naming no scopes at all, so the
 * least deliberate way to fill this form — type a name, tick nothing,
 * click — produced a credential that could reach the taxonomy, the
 * moderation queue, and every user's role. The server refuses that now;
 * these cover the half of the fix that has to happen where the person is
 * actually looking.
 */
describe('ProfileSettingsPage — access tokens', () => {
  const nameIt = async (label: string) => {
    fireEvent.change(await screen.findByLabelText('Token name'), { target: { value: label } });
  };

  it('will not create a token until some authority has been chosen', async () => {
    render(<ProfileSettingsPage />);
    await nameIt('Claude Code');

    expect(screen.getByText('Create token')).toBeDisabled();

    fireEvent.click(screen.getByText('discovery:read'));
    await waitFor(() => expect(screen.getByText('Create token')).toBeEnabled());
  });

  it('sends the wildcard when full access is the choice', async () => {
    render(<ProfileSettingsPage />);
    await nameIt('ops');

    fireEvent.click(await screen.findByText('full access'));
    fireEvent.click(screen.getByText('Create token'));

    await waitFor(() => expect(mockCreateToken).toHaveBeenCalledWith('ops', ['*']));
  });

  // Ticking both would show a set of narrow chips beside a wildcard that
  // silently overrules every one of them — a grant that reads as limited
  // and behaves as total, which is the confusion this whole change is
  // about.
  it('treats full access and a narrow grant as alternatives', async () => {
    render(<ProfileSettingsPage />);
    const chip = async (label: string) => await screen.findByText(label);

    fireEvent.click(await chip('discovery:read'));
    fireEvent.click(await chip('full access'));

    expect(await chip('full access')).toHaveAttribute('aria-pressed', 'true');
    expect(await chip('discovery:read')).toHaveAttribute('aria-pressed', 'false');

    // And back the other way, so neither is a trap door.
    fireEvent.click(await chip('profile:write'));

    expect(await chip('profile:write')).toHaveAttribute('aria-pressed', 'true');
    expect(await chip('full access')).toHaveAttribute('aria-pressed', 'false');
  });

  it('says plainly which existing tokens hold everything', async () => {
    mockListTokens.mockResolvedValue({
      tokens: [
        { id: 't-1', name: 'ops', scopes: ['*'], created_at: '2026-08-14T00:00:00Z', last_used_at: null },
        { id: 't-2', name: 'reader', scopes: ['discovery:read'], created_at: '2026-08-14T00:00:00Z', last_used_at: null },
      ],
      scopes: ['discovery:read', 'profile:write'],
      full_access_scope: '*',
    });
    render(<ProfileSettingsPage />);

    expect(await screen.findByText(/full access ·/)).toBeInTheDocument();
    expect(screen.getByText(/discovery:read ·/)).toBeInTheDocument();
  });
});
