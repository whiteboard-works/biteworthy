import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { BrandingEditor } from '../_BrandingEditor';

/**
 * The editor's contract with the API: only changed slots go in the
 * form (an untouched image must not be re-sent or cleared), removal is a
 * flag, and a 403 is explained as an ownership problem rather than a
 * generic failure.
 */

vi.mock('../../lib/shrink-image', () => ({
  MAX_UPLOAD_BYTES: 4 * 1024 * 1024,
  shrinkForUpload: async (file: File) => file,
  tooLargeToUpload: (file: File) => file.size > 4 * 1024 * 1024,
}));

const current = { logo_url: 'https://img.test/logo.webp', banner_url: null };

function okResponse(body: unknown): Response {
  return { ok: true, status: 200, json: async () => body } as unknown as Response;
}

beforeEach(() => {
  vi.stubGlobal('URL', { ...URL, createObjectURL: () => 'blob:preview' });
});

describe('BrandingEditor', () => {
  it('sends only the picked banner, leaving the existing logo alone', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(
        okResponse({
          logo_url: 'https://img.test/logo.webp',
          banner_url: 'https://img.test/b.webp',
        }),
      );
    const onSaved = vi.fn();
    render(
      <BrandingEditor
        endpoint="/api/restaurants/ninis/branding"
        current={current}
        onSaved={onSaved}
        fetchImpl={fetchImpl}
      />,
    );

    expect(screen.getByTestId('branding-save')).toBeDisabled();
    const file = new File(['x'], 'banner.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByTestId('branding-banner-input'), { target: { files: [file] } });
    await waitFor(() => expect(screen.getByTestId('branding-banner-preview')).toBeInTheDocument());

    fireEvent.click(screen.getByTestId('branding-save'));
    await waitFor(() => expect(onSaved).toHaveBeenCalled());

    const [url, init] = fetchImpl.mock.calls[0] as [string, { method: string; body: FormData }];
    expect(url).toBe('/api/restaurants/ninis/branding');
    expect(init.method).toBe('PATCH');
    expect(init.body.get('banner')).toBe(file);
    expect(init.body.has('logo')).toBe(false);
    expect(init.body.has('remove_logo')).toBe(false);
    expect(onSaved).toHaveBeenCalledWith({
      logo_url: 'https://img.test/logo.webp',
      banner_url: 'https://img.test/b.webp',
    });
  });

  it('removes an image with the flag instead of a file', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(okResponse({ logo_url: null, banner_url: null }));
    render(
      <BrandingEditor
        endpoint="/api/restaurants/ninis/branding"
        current={current}
        onSaved={vi.fn()}
        fetchImpl={fetchImpl}
      />,
    );

    fireEvent.click(screen.getByTestId('branding-logo-remove'));
    expect(screen.queryByTestId('branding-logo-preview')).toBeNull();
    fireEvent.click(screen.getByTestId('branding-save'));
    await waitFor(() => expect(fetchImpl).toHaveBeenCalled());

    const [, init] = fetchImpl.mock.calls[0] as [string, { body: FormData }];
    expect(init.body.get('remove_logo')).toBe('true');
    expect(init.body.has('logo')).toBe(false);
  });

  it('explains a 403 as an ownership problem', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false,
      status: 403,
      json: async () => ({ error: 'Only the verified owner…' }),
    } as unknown as Response);
    const onSaved = vi.fn();
    render(
      <BrandingEditor
        endpoint="/api/restaurants/ninis/branding"
        current={current}
        onSaved={onSaved}
        fetchImpl={fetchImpl}
      />,
    );

    fireEvent.click(screen.getByTestId('branding-logo-remove'));
    fireEvent.click(screen.getByTestId('branding-save'));

    await waitFor(() =>
      expect(screen.getByTestId('branding-error')).toHaveTextContent('Only the verified owner'),
    );
    expect(onSaved).not.toHaveBeenCalled();
  });
});
