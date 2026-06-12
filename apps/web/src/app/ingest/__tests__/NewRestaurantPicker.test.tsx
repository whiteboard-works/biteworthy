import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { NewRestaurantPicker } from '../_NewRestaurantPicker';
import * as ingestion from '../../../lib/ingestion';

vi.mock('../../../lib/ingestion', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../lib/ingestion')>();
  return { ...actual, createRestaurant: vi.fn() };
});

const createRestaurantMock = vi.mocked(ingestion.createRestaurant);

// NOTE: no beforeEach mock-clearing — see VerifyItemRow.test.tsx for
// the vitest-4 unhandled-rejection quirk this avoids. Tests use
// per-test impls + call-count deltas instead.
describe('NewRestaurantPicker', () => {

  it('calls onPicked with the created restaurant', async () => {
    createRestaurantMock.mockResolvedValue({
      kind: 'created',
      restaurant: { id: 'r-1', slug: 'marias', name: "Maria's Tacos", status: 'draft' },
    });
    const onPicked = vi.fn();
    render(<NewRestaurantPicker onPicked={onPicked} />);

    fireEvent.change(screen.getByPlaceholderText("Maria's Tacos"), {
      target: { value: "Maria's Tacos" },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Create restaurant' }));

    await waitFor(() =>
      expect(onPicked).toHaveBeenCalledWith({ id: 'r-1', name: "Maria's Tacos" }),
    );
  });

  it('renders "did you mean" cards on duplicates; picking one calls onPicked with the existing id', async () => {
    createRestaurantMock.mockResolvedValue({
      kind: 'duplicates',
      candidates: [
        { id: 'r-9', slug: 'marias', name: "Maria's Tacos", status: 'published', street: '742 Main Ave' },
      ],
    });
    const onPicked = vi.fn();
    render(<NewRestaurantPicker onPicked={onPicked} />);

    fireEvent.change(screen.getByPlaceholderText("Maria's Tacos"), {
      target: { value: 'Marias Taco' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Create restaurant' }));

    await screen.findByText('Did you mean one of these?');
    expect(screen.getByText('742 Main Ave · published')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Use this one' }));
    expect(onPicked).toHaveBeenCalledWith({ id: 'r-9', name: "Maria's Tacos" });
  });

  it('"create anyway" re-submits with force', async () => {
    createRestaurantMock
      .mockResolvedValueOnce({
        kind: 'duplicates',
        candidates: [
          { id: 'r-9', slug: 'marias', name: "Maria's Tacos", status: 'published', street: null },
        ],
      })
      .mockResolvedValueOnce({
        kind: 'created',
        restaurant: { id: 'r-2', slug: 'marias-taco', name: 'Marias Taco', status: 'draft' },
      });
    const onPicked = vi.fn();
    render(<NewRestaurantPicker onPicked={onPicked} />);

    fireEvent.change(screen.getByPlaceholderText("Maria's Tacos"), {
      target: { value: 'Marias Taco' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Create restaurant' }));
    await screen.findByText('Did you mean one of these?');

    fireEvent.click(screen.getByRole('button', { name: /create “Marias Taco” anyway/ }));

    await waitFor(() => expect(onPicked).toHaveBeenCalledWith({ id: 'r-2', name: 'Marias Taco' }));
    expect(createRestaurantMock).toHaveBeenLastCalledWith(
      expect.objectContaining({ force: true }),
    );
  });

  it('shows a validation error when the name is blank', async () => {
    const callsBefore = createRestaurantMock.mock.calls.length;
    const onPicked = vi.fn();
    render(<NewRestaurantPicker onPicked={onPicked} />);

    fireEvent.click(screen.getByRole('button', { name: 'Create restaurant' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Restaurant name is required.');
    expect(createRestaurantMock.mock.calls.length).toBe(callsBefore);
  });
});
