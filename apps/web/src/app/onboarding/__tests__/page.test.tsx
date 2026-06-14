import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * Phase 8.5 — web taste-onboarding step.
 *
 * The pure cycle (neutral → liked → disliked → neutral) is covered in
 * the filter-engine reducer spec, and the saveTaste/fetchTags wire
 * shapes in `lib/__tests__/onboarding.test.ts`. This file targets the
 * React page: that the taste chips render + cycle, that standalone
 * `?step=taste` saves ONLY the taste arrays (toTastePayload, can't
 * wipe avoid lists), and that the full flow's taste step is skippable.
 */

const mockReplace = vi.fn();
const mockGet = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  useSearchParams: () => ({ get: mockGet }),
}));

const mockFetchDietaryProfiles = vi.fn();
const mockFetchTags = vi.fn();
const mockSearchIngredients = vi.fn();
const mockSaveProfile = vi.fn();
const mockSaveTaste = vi.fn();
vi.mock('../../../lib/onboarding', () => ({
  fetchDietaryProfiles: (...a: unknown[]) => mockFetchDietaryProfiles(...a),
  fetchTags: (...a: unknown[]) => mockFetchTags(...a),
  searchIngredients: (...a: unknown[]) => mockSearchIngredients(...a),
  saveProfile: (...a: unknown[]) => mockSaveProfile(...a),
  saveTaste: (...a: unknown[]) => mockSaveTaste(...a),
}));

vi.mock('../../_PostHogProvider', () => ({
  useTracker: () => ({ track: vi.fn() }),
}));

import OnboardingPage from '../page';

const THAI = { id: 'tag-thai', slug: 'cuisine-thai', name: 'Thai', family: 'cuisine' };

beforeEach(() => {
  mockReplace.mockReset();
  mockGet.mockReset();
  mockFetchDietaryProfiles.mockReset().mockResolvedValue([]);
  mockFetchTags.mockReset().mockResolvedValue([THAI]);
  mockSearchIngredients.mockReset().mockResolvedValue([]);
  mockSaveProfile.mockReset().mockResolvedValue(undefined);
  mockSaveTaste.mockReset().mockResolvedValue(undefined);
});

afterEach(() => {
  vi.clearAllTimers();
});

describe('OnboardingPage — taste step (standalone "Improve my picks")', () => {
  beforeEach(() => mockGet.mockReturnValue('taste'));

  it('opens directly on the taste step with the standalone framing', async () => {
    render(<OnboardingPage />);
    expect(await screen.findByText('What do you love?')).toBeInTheDocument();
    expect(screen.getByText('Improve your picks')).toBeInTheDocument();
    // No "Step X of 5" eyebrow in standalone mode.
    expect(screen.queryByText(/Step \d of 5/)).not.toBeInTheDocument();
    expect(screen.getByTestId('save-taste')).toBeInTheDocument();
  });

  it('cycles a tag chip neutral → liked on tap and saves only taste arrays', async () => {
    render(<OnboardingPage />);
    const chip = await screen.findByTestId('taste-tag-cuisine-thai');
    expect(chip).toHaveAttribute('data-state', 'neutral');

    fireEvent.click(chip);
    expect(screen.getByTestId('taste-tag-cuisine-thai')).toHaveAttribute('data-state', 'liked');

    await act(async () => {
      fireEvent.click(screen.getByTestId('save-taste'));
    });

    await waitFor(() => expect(mockSaveTaste).toHaveBeenCalledTimes(1));
    expect(mockSaveTaste.mock.calls[0]![0]).toEqual({
      liked_tag_ids: ['tag-thai'],
      disliked_tag_ids: [],
      liked_ingredient_ids: [],
      disliked_ingredient_ids: [],
    });
    // The footgun guard: a taste save must NOT touch the avoid lists.
    expect(mockSaveProfile).not.toHaveBeenCalled();
    expect(mockReplace).toHaveBeenCalledWith('/');
  });

  it('Cancel leaves without saving', async () => {
    render(<OnboardingPage />);
    await screen.findByTestId('skip-taste');
    fireEvent.click(screen.getByTestId('skip-taste'));
    expect(mockSaveTaste).not.toHaveBeenCalled();
    expect(mockReplace).toHaveBeenCalledWith('/');
  });
});

describe('OnboardingPage — taste step in the full flow', () => {
  beforeEach(() => mockGet.mockReturnValue(null));

  it('sits at step 4 of 5 between strictness and review, and is skippable', async () => {
    render(<OnboardingPage />);
    // presets (1) → ingredients (2) → strictness (3) → taste (4)
    fireEvent.click(await screen.findByTestId('next-to-ingredients'));
    fireEvent.click(screen.getByTestId('next-to-strictness'));
    fireEvent.click(screen.getByTestId('next-to-taste'));

    expect(screen.getByText('Step 4 of 5')).toBeInTheDocument();
    expect(screen.getByText('What do you love?')).toBeInTheDocument();

    // Skip for now → review step (taste arrays stay empty).
    fireEvent.click(screen.getByTestId('skip-taste'));
    expect(screen.getByText('Step 5 of 5')).toBeInTheDocument();
    expect(screen.getByText('Ready?')).toBeInTheDocument();
  });
});

describe('OnboardingPage — allergen acknowledgment (legal E1)', () => {
  beforeEach(() => mockGet.mockReturnValue(null));

  const goToReview = async () => {
    render(<OnboardingPage />);
    fireEvent.click(await screen.findByTestId('next-to-ingredients'));
    fireEvent.click(screen.getByTestId('next-to-strictness'));
    fireEvent.click(screen.getByTestId('next-to-taste'));
    fireEvent.click(screen.getByTestId('skip-taste'));
  };

  it('blocks the save until the disclaimer is acknowledged, then records it', async () => {
    await goToReview();

    // Save is disabled and saveProfile is never called while unchecked.
    expect(screen.getByTestId('finish')).toBeDisabled();
    await act(async () => {
      fireEvent.click(screen.getByTestId('finish'));
    });
    expect(mockSaveProfile).not.toHaveBeenCalled();

    // Check the box → save enables and sends acknowledge_disclaimer.
    fireEvent.click(screen.getByTestId('acknowledge-disclaimer'));
    expect(screen.getByTestId('finish')).not.toBeDisabled();

    await act(async () => {
      fireEvent.click(screen.getByTestId('finish'));
    });
    await waitFor(() => expect(mockSaveProfile).toHaveBeenCalledTimes(1));
    expect(mockSaveProfile.mock.calls[0]![0]).toMatchObject({ acknowledge_disclaimer: true });
  });
});
