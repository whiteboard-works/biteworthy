import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import PrivacyPage from '../page';

/**
 * WBW-173 — the Pixel is live; this page has to name Meta and say the
 * existing opt-out covers it, not only PostHog.
 */
describe('PrivacyPage — Meta Pixel disclosure', () => {
  it('names Meta Platforms and that the opt-out covers PostHog and Meta', () => {
    render(<PrivacyPage />);
    expect(screen.getByText(/Meta Platforms, Inc\./)).toBeInTheDocument();
    expect(screen.getByText(/same opt-out as PostHog/)).toBeInTheDocument();
    expect(screen.getByText(/analytics \(PostHog and Meta Pixel\)/)).toBeInTheDocument();
  });
});
