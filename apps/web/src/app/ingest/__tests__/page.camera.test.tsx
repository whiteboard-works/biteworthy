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

  it('accepts multiple files at once via the picker', () => {
    render(<IngestPage />);
    // The file picker is multi-select so a whole menu can upload as one run.
    expect(screen.getByTestId('file-input')).toHaveAttribute('multiple');

    const page1 = new File(['a'], 'page-1.jpg', { type: 'image/jpeg' });
    const page2 = new File(['b'], 'page-2.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByTestId('file-input'), { target: { files: [page1, page2] } });

    const list = screen.getByTestId('selected-file');
    expect(list).toHaveTextContent('page-1.jpg');
    expect(list).toHaveTextContent('page-2.jpg');
  });

  it('accumulates repeated camera captures into the same run instead of replacing', () => {
    render(<IngestPage />);
    const shot1 = new File(['a'], 'shot-1.jpg', { type: 'image/jpeg' });
    const shot2 = new File(['b'], 'shot-2.jpg', { type: 'image/jpeg' });

    fireEvent.change(screen.getByTestId('camera-input'), { target: { files: [shot1] } });
    fireEvent.change(screen.getByTestId('camera-input'), { target: { files: [shot2] } });

    const list = screen.getByTestId('selected-file');
    expect(list).toHaveTextContent('shot-1.jpg');
    expect(list).toHaveTextContent('shot-2.jpg');
  });

  it('removes a single selected file without clearing the rest', () => {
    render(<IngestPage />);
    const page1 = new File(['a'], 'page-1.jpg', { type: 'image/jpeg' });
    const page2 = new File(['b'], 'page-2.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByTestId('file-input'), { target: { files: [page1, page2] } });

    fireEvent.click(screen.getByLabelText('Remove page-1.jpg'));

    const list = screen.getByTestId('selected-file');
    expect(list).not.toHaveTextContent('page-1.jpg');
    expect(list).toHaveTextContent('page-2.jpg');
  });
});
