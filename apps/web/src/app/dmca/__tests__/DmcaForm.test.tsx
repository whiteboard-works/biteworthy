import { afterEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { DmcaForm } from '../DmcaForm';

/**
 * Legal remediation E10 — the DMCA form must require both §512(c)(3)
 * sworn statements before it will submit, and post the structured
 * notice to the proxy.
 */
describe('DmcaForm', () => {
  afterEach(() => vi.restoreAllMocks());

  const fill = () => {
    fireEvent.change(screen.getByLabelText('dmca-name'), { target: { value: 'Jane' } });
    fireEvent.change(screen.getByLabelText('dmca-email'), { target: { value: 'jane@example.com' } });
    fireEvent.change(screen.getByLabelText('dmca-url'), { target: { value: 'https://x/y' } });
    fireEvent.change(screen.getByLabelText('dmca-description'), { target: { value: 'My photo.' } });
    fireEvent.change(screen.getByLabelText('dmca-signature'), { target: { value: 'Jane Counsel' } });
  };

  it('keeps submit disabled until both sworn statements are checked', () => {
    render(<DmcaForm />);
    fill();
    expect(screen.getByTestId('dmca-submit')).toBeDisabled();

    fireEvent.click(screen.getByLabelText('dmca-good-faith'));
    expect(screen.getByTestId('dmca-submit')).toBeDisabled();

    fireEvent.click(screen.getByLabelText('dmca-accuracy'));
    expect(screen.getByTestId('dmca-submit')).not.toBeDisabled();
  });

  it('posts the notice and shows a confirmation on success', async () => {
    const fetchMock = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue({ ok: true, json: async () => ({ ok: true }) } as Response);

    render(<DmcaForm />);
    fill();
    fireEvent.click(screen.getByLabelText('dmca-good-faith'));
    fireEvent.click(screen.getByLabelText('dmca-accuracy'));
    fireEvent.click(screen.getByTestId('dmca-submit'));

    await waitFor(() => expect(screen.getByTestId('dmca-done')).toBeInTheDocument());

    const [url, init] = fetchMock.mock.calls[0]!;
    expect(url).toBe('/api/dmca');
    expect(JSON.parse((init as RequestInit).body as string)).toMatchObject({
      complainant_email: 'jane@example.com',
      good_faith: true,
      accuracy_sworn: true,
    });
  });
});
