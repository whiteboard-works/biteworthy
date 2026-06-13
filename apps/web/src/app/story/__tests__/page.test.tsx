import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import StoryPage, { metadata } from '../page';

/**
 * The /story page is the user-facing telling of docs/vision.md. The
 * thing worth locking is that the product principle and the call to
 * action actually render — copy can change, but "safety filters, taste
 * ranks" and the path into the app are the spine.
 */

describe('StoryPage', () => {
  it('leads with the value-prop headline', () => {
    render(<StoryPage />);
    expect(screen.getByTestId('story-headline')).toHaveTextContent(/leap of faith/i);
  });

  it('states the safety-vs-taste principle verbatim', () => {
    render(<StoryPage />);
    expect(screen.getByTestId('story-principle')).toHaveTextContent('Safety filters. Taste ranks.');
  });

  it('explains honest disclosure (strict mode + why)', () => {
    render(<StoryPage />);
    expect(screen.getByText(/strict mode/i)).toBeInTheDocument();
  });

  it('drives into the onboarding flow', () => {
    render(<StoryPage />);
    expect(screen.getByTestId('story-cta')).toHaveAttribute('href', '/onboarding');
  });

  it('sets canonical metadata for /story', () => {
    expect(metadata.title).toBe('Our story — BiteWorthy');
    expect(metadata.alternates?.canonical).toBe('/story');
  });
});
