// Mock expo-router so importing the screen module doesn't pull the
// full Stack/Tabs runtime — we only need its named exports here.
jest.mock('expo-router', () => ({
  router: { push: jest.fn(), replace: jest.fn(), back: jest.fn() },
  useLocalSearchParams: () => ({}),
  Link: 'Link',
}));

import { render, screen } from '@testing-library/react-native';
import { HiddenReasonChip, StrictnessToggle } from '../../app/restaurants/[id]';

/**
 * Phase post-5 — first JSX render tests for the mobile app.
 *
 * Targets the already-exported helpers (HiddenReasonChip,
 * StrictnessToggle) on the restaurant screen — same as the web
 * counterpart in PR #189. Proves the jest-expo + testing-library/
 * react-native infra works end-to-end on Expo SDK 52.
 *
 * The Phase 4.11.4 ItemRow photo_url contract on mobile isn't
 * covered here — ItemRow is a file-private component inside
 * `app/restaurants/[id].tsx`, and extracting it is a separate
 * scoped follow-up (mirrors the web pattern from PR #190).
 */

describe('HiddenReasonChip (mobile)', () => {
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
    expect(screen.getByTestId('chip-avoid_ingredient')).toBeOnTheScreen();
    expect(screen.getByText('Contains dairy (Cheddar)')).toBeOnTheScreen();
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
    expect(screen.getByText('Tagged allergen: Contains Dairy')).toBeOnTheScreen();
  });

  it('renders the unconfirmed_strict label with the confidence value', () => {
    render(
      <HiddenReasonChip
        reason={{ kind: 'unconfirmed_strict', confidence: 'inferred' }}
      />,
    );
    expect(screen.getByText(/inferred/)).toBeOnTheScreen();
  });
});

describe('StrictnessToggle (mobile)', () => {
  it('renders all three strictness modes with the active one selected', () => {
    render(
      <StrictnessToggle active="balanced" loading={false} onChange={() => {}} />,
    );

    const balanced = screen.getByLabelText('strictness-balanced');
    expect(balanced).toBeOnTheScreen();
    expect(balanced.props.accessibilityState).toMatchObject({ selected: true, disabled: false });

    const strict = screen.getByLabelText('strictness-strict');
    expect(strict.props.accessibilityState).toMatchObject({ selected: false, disabled: false });
  });

  it('disables every Pressable + shows the spinner while loading', () => {
    render(
      <StrictnessToggle active="strict" loading={true} onChange={() => {}} />,
    );
    const relaxed = screen.getByLabelText('strictness-relaxed');
    expect(relaxed.props.accessibilityState).toMatchObject({ selected: false, disabled: true });
    expect(screen.getByTestId('strictness-spinner')).toBeOnTheScreen();
  });
});
