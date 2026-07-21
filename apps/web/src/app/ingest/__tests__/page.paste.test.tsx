import { beforeEach, describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, act, waitFor } from '@testing-library/react';

const push = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push, replace: vi.fn() }),
}));

const ingestFromText = vi.fn();
vi.mock('../../../lib/ingestion', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../lib/ingestion')>();
  return { ...actual, ingestFromText: (...a: unknown[]) => ingestFromText(...a) };
});

import IngestPage from '../page';

// Provide a restaurant id via the manual-UUID escape hatch so submit clears
// the "pick a restaurant first" guard without driving NewRestaurantPicker.
function setRestaurant() {
  fireEvent.change(screen.getByPlaceholderText(/aaaaaaaa/), {
    target: { value: 'rest-uuid-1' },
  });
}

beforeEach(() => {
  push.mockReset();
  ingestFromText.mockReset();
});

describe('IngestPage — paste menu text', () => {
  it('imports pasted text via ingestFromText and routes to the verify page', async () => {
    ingestFromText.mockResolvedValue({ id: 'run-77' });
    render(<IngestPage />);
    setRestaurant();

    fireEvent.change(screen.getByTestId('paste-input'), {
      target: { value: 'Appetizers\nHummus — chickpeas, tahini … 8' },
    });
    await act(async () => {
      fireEvent.click(screen.getByTestId('paste-submit'));
    });

    await waitFor(() => expect(ingestFromText).toHaveBeenCalledTimes(1));
    expect(ingestFromText.mock.calls[0]![0]).toMatchObject({
      restaurantId: 'rest-uuid-1',
      sourceText: 'Appetizers\nHummus — chickpeas, tahini … 8',
    });
    expect(push).toHaveBeenCalledWith('/ingest/verify/run-77');
  });

  it('blocks submit and warns when the textarea is empty', async () => {
    render(<IngestPage />);
    setRestaurant();

    await act(async () => {
      fireEvent.click(screen.getByTestId('paste-submit'));
    });

    expect(ingestFromText).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('Paste the menu text.');
  });
});
