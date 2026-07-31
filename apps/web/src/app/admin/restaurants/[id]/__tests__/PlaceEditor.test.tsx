import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

/**
 * Hours save as a WHOLE week, matching the API — a per-day write could
 * land half-applied and advertise the wrong opening time. The two
 * conversions that matter: a day with no stored row reads as closed,
 * and ticking Closed sends explicit nulls (which is how the schema
 * encodes it) rather than dropping the day.
 */

const mockFetchPlace = vi.fn();
const mockSaveAddress = vi.fn();
const mockSaveHours = vi.fn();
vi.mock('../../../../../lib/admin/structure', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/structure')>()),
  fetchAdminPlace: (id: string) => mockFetchPlace(id),
  saveAddress: (id: string, body: unknown) => mockSaveAddress(id, body),
  saveHours: (id: string, hours: unknown) => mockSaveHours(id, hours),
}));

import { PlaceEditor } from '../_PlaceEditor';

const place = {
  restaurant_id: 'r1',
  address: { id: 'a1', street: '1 Elm', city: 'Durango', region: 'CO', postal_code: '81301', country: 'US' },
  hours: [{ id: 'h1', day_of_week: 1, opens_at: '11:00', closes_at: '21:00' }],
};

beforeEach(() => {
  mockFetchPlace.mockReset().mockResolvedValue(place);
  mockSaveAddress.mockReset().mockResolvedValue(place);
  mockSaveHours.mockReset().mockResolvedValue(place);
});

describe('PlaceEditor', () => {
  it('seeds the address form and marks days without a row as closed', async () => {
    render(<PlaceEditor restaurantId="r1" />);

    expect(await screen.findByTestId('address-street')).toHaveValue('1 Elm');
    // Monday has hours; Sunday has no row at all.
    expect(screen.getByTestId('hours-opens-1')).toHaveValue('11:00');
    expect(screen.getByTestId('hours-closed-1')).not.toBeChecked();
    expect(screen.getByTestId('hours-closed-0')).toBeChecked();
    expect(screen.getByTestId('hours-opens-0')).toBeDisabled();
  });

  it('submits the whole week, sending nulls for closed days', async () => {
    render(<PlaceEditor restaurantId="r1" />);
    await screen.findByTestId('hours-grid');

    fireEvent.click(screen.getByTestId('hours-closed-2'));
    fireEvent.change(screen.getByTestId('hours-opens-2'), { target: { value: '09:00' } });
    fireEvent.change(screen.getByTestId('hours-closes-2'), { target: { value: '15:00' } });
    fireEvent.click(screen.getByTestId('hours-save'));

    await vi.waitFor(() => expect(mockSaveHours).toHaveBeenCalled());
    const rows = mockSaveHours.mock.calls.at(-1)![1] as Array<Record<string, unknown>>;
    // Every day travels: the open ones with times, the closed ones with
    // explicit nulls.
    expect(rows).toHaveLength(7);
    expect(rows.find((r) => r.day_of_week === 1)).toEqual({
      day_of_week: 1,
      opens_at: '11:00',
      closes_at: '21:00',
    });
    expect(rows.find((r) => r.day_of_week === 2)).toEqual({
      day_of_week: 2,
      opens_at: '09:00',
      closes_at: '15:00',
    });
    expect(rows.find((r) => r.day_of_week === 0)).toEqual({
      day_of_week: 0,
      opens_at: null,
      closes_at: null,
    });
  });

  it('saves the address fields as typed', async () => {
    render(<PlaceEditor restaurantId="r1" />);
    await screen.findByTestId('address-street');

    fireEvent.change(screen.getByTestId('address-street'), { target: { value: '2 Oak' } });
    fireEvent.click(screen.getByTestId('address-save'));

    await vi.waitFor(() => expect(mockSaveAddress).toHaveBeenCalled());
    expect(mockSaveAddress.mock.calls.at(-1)![1]).toMatchObject({ street: '2 Oak', city: 'Durango' });
  });

  it('turns a server refusal into instructions', async () => {
    const { AdminError } = await import('../../../../../lib/admin/shared');
    mockSaveHours.mockRejectedValue(
      new AdminError('x', 422, 'invalid_time_of_day', {
        error: 'invalid_time_of_day',
        values: ['25:99'],
      }),
    );
    render(<PlaceEditor restaurantId="r1" />);
    await screen.findByTestId('hours-grid');

    fireEvent.click(screen.getByTestId('hours-save'));

    expect(await screen.findByTestId('place-error')).toHaveTextContent(/25:99/);
  });
});
