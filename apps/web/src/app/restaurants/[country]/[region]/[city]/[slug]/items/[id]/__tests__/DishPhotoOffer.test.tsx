import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { DishPhotoOffer } from '../_DishPhotoOffer';

const mockSubmit = vi.fn();
vi.mock('../../../../../../../../../lib/photo-submissions', () => ({
  submitDishPhoto: (...args: unknown[]) => mockSubmit(...args),
  PhotoSubmissionError: class extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.status = status;
    }
  },
}));

const mockReplace = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
}));

beforeEach(() => {
  mockSubmit.mockReset();
  mockReplace.mockReset();
  URL.createObjectURL ??= (() => 'blob:preview') as typeof URL.createObjectURL;
  URL.revokeObjectURL ??= (() => undefined) as typeof URL.revokeObjectURL;
});

describe('DishPhotoOffer', () => {
  it('sends a signed-out visitor to sign in with a return path', () => {
    render(
      <DishPhotoOffer
        itemId="item-1"
        returnPath="/restaurants/usa/colorado/durango/nini/items/item-1?addPhoto=1"
        signedIn={false}
      />,
    );
    fireEvent.click(screen.getByTestId('add-dish-photo'));
    expect(mockReplace).toHaveBeenCalledWith(
      '/login?next=%2Frestaurants%2Fusa%2Fcolorado%2Fdurango%2Fnini%2Fitems%2Fitem-1%3FaddPhoto%3D1',
    );
    expect(screen.queryByTestId('dish-photo-form')).not.toBeInTheDocument();
  });

  it('redirects a signed-out addPhoto=1 deep link before the form opens', () => {
    render(
      <DishPhotoOffer
        itemId="item-1"
        returnPath="/restaurants/usa/colorado/durango/nini/items/item-1?addPhoto=1"
        signedIn={false}
        startOpen
      />,
    );
    expect(mockReplace).toHaveBeenCalledWith(
      '/login?next=%2Frestaurants%2Fusa%2Fcolorado%2Fdurango%2Fnini%2Fitems%2Fitem-1%3FaddPhoto%3D1',
    );
    expect(screen.queryByTestId('dish-photo-form')).not.toBeInTheDocument();
  });

  it('requires the rights checkbox before submit, then shows the thanks line', async () => {
    mockSubmit.mockResolvedValue({ id: 'sub-1', status: 'pending' });
    render(<DishPhotoOffer itemId="item-1" returnPath="/x" signedIn startOpen />);

    const file = new File(['img'], 'taco.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByLabelText('dish-photo'), { target: { files: [file] } });
    fireEvent.click(screen.getByTestId('submit-dish-photo'));
    expect(await screen.findByText(/confirm you took this photo/i)).toBeInTheDocument();
    expect(mockSubmit).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('owns-rights'));
    fireEvent.click(screen.getByTestId('submit-dish-photo'));

    expect(await screen.findByTestId('photo-thanks')).toHaveTextContent(
      'Thanks, a moderator will review it.',
    );
    expect(mockSubmit).toHaveBeenCalledWith('item-1', file);
  });

  it('shows Preview unavailable when the browser cannot decode the file', () => {
    render(<DishPhotoOffer itemId="item-1" returnPath="/x" signedIn startOpen />);
    const file = new File(['not-an-image'], 'weird.webp', { type: 'image/webp' });
    fireEvent.change(screen.getByLabelText('dish-photo'), { target: { files: [file] } });
    fireEvent.error(screen.getByTestId('dish-photo-preview'));
    expect(screen.getByTestId('preview-unavailable')).toHaveTextContent('Preview unavailable');
    expect(screen.queryByTestId('dish-photo-preview')).not.toBeInTheDocument();
  });

  it('clears the rights checkbox when the diner picks a different file', () => {
    render(<DishPhotoOffer itemId="item-1" returnPath="/x" signedIn startOpen />);
    const first = new File(['img'], 'taco.jpg', { type: 'image/jpeg' });
    const second = new File(['img2'], 'burrito.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByLabelText('dish-photo'), { target: { files: [first] } });
    fireEvent.click(screen.getByTestId('owns-rights'));
    expect(screen.getByTestId('owns-rights')).toBeChecked();

    fireEvent.change(screen.getByLabelText('dish-photo'), { target: { files: [second] } });
    expect(screen.getByTestId('owns-rights')).not.toBeChecked();
  });
});
