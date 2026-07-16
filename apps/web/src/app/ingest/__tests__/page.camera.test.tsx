import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import IngestPage from '../page';

// The page only pulls useRouter from next/navigation; NewRestaurantPicker
// (rendered inside it) is inert on mount — see NewRestaurantPicker.test.tsx.
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

describe('IngestPage — camera capture', () => {
  it('offers a rear-camera capture input for menu photos', () => {
    render(<IngestPage />);
    const camera = screen.getByTestId('camera-input');
    // capture="environment" is what makes mobile browsers open the rear
    // camera directly instead of the gallery/file picker.
    expect(camera).toHaveAttribute('capture', 'environment');
    expect(camera).toHaveAttribute('accept', 'image/*');
  });

  it('confirms the captured photo by name so a hidden-input capture is visible feedback', () => {
    render(<IngestPage />);
    const photo = new File(['x'], 'menu.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByTestId('camera-input'), { target: { files: [photo] } });
    expect(screen.getByTestId('selected-file')).toHaveTextContent('menu.jpg');
  });
});
