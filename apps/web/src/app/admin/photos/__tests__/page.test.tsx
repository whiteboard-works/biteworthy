import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import AdminPhotosPage from '../page';

const mockFetch = vi.fn();
const mockApprove = vi.fn();
const mockReject = vi.fn();
vi.mock('../../../../lib/admin/photo-submissions', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/photo-submissions')>()),
  fetchPhotoSubmissions: (q: unknown) => mockFetch(q),
  approvePhotoSubmission: (id: string, replace: boolean) => mockApprove(id, replace),
  rejectPhotoSubmission: (id: string, reason: string) => mockReject(id, reason),
}));

function row(overrides: Record<string, unknown> = {}) {
  return {
    id: 'sub-1',
    item_id: 'i1',
    status: 'pending',
    rejection_reason: null,
    owns_rights: true,
    review_id: null,
    photo_url: 'https://example.com/submitted.jpg',
    credit_name: 'Pat Diner',
    created_at: '2026-10-06T12:00:00Z',
    reviewed_at: null,
    user: { id: 'u1', handle: 'pat_diner', display_name: 'Pat Diner' },
    item: {
      id: 'i1',
      name: 'Carne Asada',
      photo_url: null,
      restaurant: { id: 'r1', name: "Nini's", slug: 'ninis' },
    },
    ...overrides,
  };
}

function payload(rows: unknown[]) {
  return { photo_submissions: rows, pagination: { total: rows.length, limit: 25, offset: 0 } };
}

beforeEach(() => {
  mockFetch.mockReset();
  mockApprove.mockReset();
  mockReject.mockReset();
});

describe('AdminPhotosPage', () => {
  it('loads the pending queue by default and shows the dish and submitter', async () => {
    mockFetch.mockResolvedValue(payload([row()]));
    render(<AdminPhotosPage />);
    const card = await screen.findByTestId('photo-mod-sub-1');
    expect(card).toHaveTextContent('Pat Diner');
    expect(card).toHaveTextContent('Carne Asada');
    expect(card).toHaveTextContent("Nini's");
    expect(mockFetch).toHaveBeenCalledWith(expect.objectContaining({ status: 'pending' }));
    expect(within(card).getByTestId('photo-approve-set-sub-1')).toBeInTheDocument();
    expect(within(card).queryByTestId('photo-approve-keep-sub-1')).not.toBeInTheDocument();
  });

  it('offers approve-without-replacing only when the dish already has a photo', async () => {
    mockFetch.mockResolvedValue(
      payload([row({ item: { ...row().item, photo_url: 'https://example.com/current.jpg' } })]),
    );
    mockApprove.mockResolvedValue(row({ status: 'approved' }));
    render(<AdminPhotosPage />);
    const card = await screen.findByTestId('photo-mod-sub-1');
    fireEvent.click(within(card).getByTestId('photo-approve-keep-sub-1'));
    expect(mockApprove).toHaveBeenCalledWith('sub-1', false);
  });

  it('rejects with the picked reason', async () => {
    mockFetch.mockResolvedValue(payload([row()]));
    mockReject.mockResolvedValue(row({ status: 'rejected', rejection_reason: 'not_food' }));
    render(<AdminPhotosPage />);
    const card = await screen.findByTestId('photo-mod-sub-1');
    fireEvent.change(within(card).getByTestId('photo-reason-sub-1'), {
      target: { value: 'not_food' },
    });
    fireEvent.click(within(card).getByTestId('photo-reject-sub-1'));
    expect(mockReject).toHaveBeenCalledWith('sub-1', 'not_food');
  });
});
