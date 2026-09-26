import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ScanDish } from '../../../../../lib/scans';

/**
 * The scan screen is the core loop's front door: photo in, filtered menu
 * out. What matters is that only the dishes a person left ticked reach
 * the live menu, that they land on that menu afterwards, and that a
 * failure says what to do next instead of spinning.
 */

const push = vi.fn();
const replace = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push, replace, refresh: vi.fn() }),
}));

const uploadAttachment = vi.fn();
const startScan = vi.fn();
const getScan = vi.fn();
const acceptScan = vi.fn();
const rejectScan = vi.fn();

vi.mock('../../../../../lib/scans', async () => {
  const actual = await vi.importActual<typeof import('../../../../../lib/scans')>(
    '../../../../../lib/scans',
  );
  return {
    ...actual,
    uploadAttachment: (f: File) => uploadAttachment(f),
    startScan: (r: string, s: unknown) => startScan(r, s),
    getScan: (id: string) => getScan(id),
    acceptScan: (id: string, ids: string[]) => acceptScan(id, ids),
    rejectScan: (id: string, ids: string[]) => rejectScan(id, ids),
  };
});

const { ScanClient } = await import('../_ScanClient');
const { NotSignedInError, ScanError } = await import('../../../../../lib/scans');

function dish(overrides: Partial<ScanDish>): ScanDish {
  return {
    id: 'd1',
    name: 'Carne Asada Taco',
    description: null,
    section: 'Tacos',
    decision: 'pending',
    prices: [{ size: null, price_cents: 450 }],
    ingredients: ['Beef', 'Onion'],
    tags: [],
    unresolved: { ingredients: [], tags: [] },
    needs_attention: false,
    updates_existing_item: null,
    ...overrides,
  };
}

const readyScan = (dishes: ScanDish[]) => ({
  scan_id: 'scan-1',
  status: 'staged',
  ready: true,
  failed: false,
  restaurant_id: 'r1',
  dish_count: dishes.length,
  pending_count: dishes.length,
  accepted_count: 0,
  rejected_count: 0,
  enrichment_status: 'completed',
  dishes,
});

async function scanAPhoto() {
  render(<ScanClient slug="ninis" restaurantName="Nini's" />);
  const file = new File(['x'], 'menu.jpg', { type: 'image/jpeg' });
  fireEvent.change(screen.getByLabelText('Menu photos'), { target: { files: [file] } });
  fireEvent.click(screen.getByRole('button', { name: 'Scan the menu' }));
}

describe('ScanClient', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    uploadAttachment.mockResolvedValue({ id: 'blob-1' });
    startScan.mockResolvedValue({ scan_id: 'scan-1', status: 'extracting', restaurant: {} });
    rejectScan.mockResolvedValue({ rejected: [], remaining_pending: 0 });
  });

  // Unticked in the main list means "not on the menu": recorded as
  // rejected, before the accept, so the draft-publish ratio counts it.
  it('publishes the ticked dishes, discards the unticked ones, then lands on the menu', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({ id: 'd1' }),
        dish({ id: 'd2', name: 'Not On The Menu', section: 'Tacos' }),
      ]),
    );
    acceptScan.mockResolvedValue({
      accepted: [],
      restaurant_published: true,
      remaining_pending: 1,
    });

    await scanAPhoto();

    expect(await screen.findByText('Tacos')).toBeInTheDocument();
    expect(startScan).toHaveBeenCalledWith('ninis', { attachmentIds: ['blob-1'] });

    fireEvent.click(screen.getByLabelText('Not On The Menu'));
    fireEvent.click(screen.getByRole('button', { name: 'Add 1 dish to the menu' }));

    await waitFor(() => expect(acceptScan).toHaveBeenCalledWith('scan-1', ['d1']));
    expect(rejectScan).toHaveBeenCalledWith('scan-1', ['d2']);
    expect(rejectScan.mock.invocationCallOrder[0]).toBeLessThan(
      acceptScan.mock.invocationCallOrder[0]!,
    );
    await waitFor(() => expect(push).toHaveBeenCalledWith('/restaurants/ninis'));
  });

  // Unmatched text means the filter can miss an allergen on that dish.
  it('warns about dishes whose ingredients it could not match', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({
          needs_attention: true,
          unresolved: { ingredients: ['mole negro'], tags: [] },
        }),
      ]),
    );

    await scanAPhoto();

    expect(await screen.findByText("Couldn't match: mole negro")).toBeInTheDocument();
    expect(screen.getByText('Needs a look (1)')).toBeInTheDocument();
  });

  // The filter can only hide what it can match: unmatched text or an empty
  // ingredient list would read as safe, so those need a deliberate tick.
  it('leaves dishes the filter cannot vouch for out of the default selection', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({ id: 'd1' }),
        dish({
          id: 'd2',
          name: 'Mole Enchiladas',
          needs_attention: true,
          unresolved: { ingredients: ['mole negro'], tags: [] },
        }),
        dish({ id: 'd3', name: 'Horchata', ingredients: [], needs_attention: true }),
      ]),
    );
    acceptScan.mockResolvedValue({
      accepted: [],
      restaurant_published: true,
      remaining_pending: 1,
    });

    await scanAPhoto();
    fireEvent.click(await screen.findByRole('button', { name: 'Add 1 dish to the menu' }));

    await waitFor(() => expect(acceptScan).toHaveBeenCalledWith('scan-1', ['d1']));
    // Flagged dishes are real dishes awaiting a fix, never thrown away.
    expect(rejectScan).not.toHaveBeenCalled();
  });

  it('never re-ticks a discarded dish when the accept fails after the discard landed', async () => {
    getScan
      .mockResolvedValueOnce(readyScan([dish({ id: 'd1' }), dish({ id: 'd2', name: 'Junk' })]))
      .mockResolvedValueOnce(
        readyScan([dish({ id: 'd1' }), dish({ id: 'd2', name: 'Junk', decision: 'rejected' })]),
      );
    acceptScan.mockRejectedValueOnce(new ScanError('Request failed (502)', null));

    await scanAPhoto();
    fireEvent.click(await screen.findByLabelText('Junk'));
    fireEvent.click(screen.getByRole('button', { name: 'Add 1 dish to the menu' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('502');
    expect(screen.queryByLabelText('Junk')).toBeNull();
    expect(screen.getByRole('button', { name: 'Add 1 dish to the menu' })).toBeInTheDocument();
  });

  it('shows every size with its price', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({
          prices: [
            { size: 'Small', price_cents: 400 },
            { size: 'Large', price_cents: 600 },
          ],
        }),
      ]),
    );

    await scanAPhoto();

    expect(await screen.findByText('Small $4.00 / Large $6.00')).toBeInTheDocument();
  });

  it('stops an over-limit batch before uploading anything', async () => {
    render(<ScanClient slug="ninis" restaurantName="Nini's" />);
    const files = Array.from(
      { length: 11 },
      (_, i) => new File(['x'], `p${i}.jpg`, { type: 'image/jpeg' }),
    );
    fireEvent.change(screen.getByLabelText('Menu photos'), { target: { files } });

    expect(screen.getByText(/up to 10 per scan/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Scan the menu' })).toBeDisabled();
    expect(uploadAttachment).not.toHaveBeenCalled();
  });

  it('cannot publish a dish whose ingredients it could not vouch for', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({ id: 'd1' }),
        dish({ id: 'd2', name: 'Mystery Stew', ingredients: [], needs_attention: true }),
      ]),
    );
    acceptScan.mockResolvedValue({
      accepted: [],
      restaurant_published: true,
      remaining_pending: 1,
    });

    await scanAPhoto();
    const locked = await screen.findByLabelText('Mystery Stew');
    expect(locked).toBeDisabled();
    fireEvent.click(locked);
    fireEvent.click(screen.getByRole('button', { name: 'Add 1 dish to the menu' }));

    await waitFor(() => expect(acceptScan).toHaveBeenCalledWith('scan-1', ['d1']));
  });

  it('finishes when an accept committed but its response was lost', async () => {
    getScan.mockResolvedValueOnce(readyScan([dish({ id: 'd1' })])).mockResolvedValueOnce({
      ...readyScan([dish({ id: 'd1', decision: 'accepted' })]),
      status: 'published',
    });
    acceptScan.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    await scanAPhoto();
    fireEvent.click(await screen.findByRole('button', { name: 'Add 1 dish to the menu' }));

    await waitFor(() => expect(push).toHaveBeenCalledWith('/restaurants/ninis'));
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('discards an all-junk scan without adding anything', async () => {
    getScan.mockResolvedValue(readyScan([dish({ id: 'd1', name: 'Page Header' })]));

    await scanAPhoto();
    fireEvent.click(await screen.findByLabelText('Page Header'));
    fireEvent.click(screen.getByRole('button', { name: 'Discard 1 dish' }));

    expect(await screen.findByText(/Nothing was added to the menu/)).toBeInTheDocument();
    expect(rejectScan).toHaveBeenCalledWith('scan-1', ['d1']);
    expect(acceptScan).not.toHaveBeenCalled();
  });

  // Accepting a matched dish rewrites the live one: opt-in, with the changes shown.
  it('shows what an update to a live dish would change and leaves it unticked', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({
          updates_existing_item: {
            item_id: 'i1',
            name: 'Carne Asada Taco',
            no_changes: false,
            diff: {
              description: { from: 'Old words', to: 'New words' },
              prices: {
                from: [{ size: null, price_cents: 400 }],
                to: [{ size: null, price_cents: 450 }],
              },
              added_ingredients: ['meat-beef'],
              added_tags: [],
            },
          },
        }),
      ]),
    );

    await scanAPhoto();

    expect(
      await screen.findByText(/Updates “Carne Asada Taco”, already on the menu/),
    ).toBeInTheDocument();
    expect(screen.getByText('Description: “Old words” → “New words”')).toBeInTheDocument();
    expect(screen.getByText('Price: $4.00 → $4.50')).toBeInTheDocument();
    expect(screen.getByLabelText('Carne Asada Taco')).not.toBeChecked();
  });

  it('keeps polling until the scan is ready', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan
      .mockResolvedValueOnce({ ...readyScan([]), ready: false, status: 'extracting' })
      .mockResolvedValueOnce(readyScan([dish({})]));

    await scanAPhoto();
    expect(await screen.findByText('Reading the menu…')).toBeInTheDocument();

    await vi.advanceTimersByTimeAsync(4000);
    expect(await screen.findByText('Carne Asada Taco')).toBeInTheDocument();
    expect(getScan).toHaveBeenCalledTimes(2);
    vi.useRealTimers();
  });

  it('rides out a dropped poll instead of freezing on the progress screen', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan
      .mockRejectedValueOnce(new ScanError('Request failed (502)', null))
      .mockResolvedValueOnce(readyScan([dish({})]));

    await scanAPhoto();
    expect(await screen.findByText('Reading the menu…')).toBeInTheDocument();
    await vi.advanceTimersByTimeAsync(8000);

    expect(await screen.findByText('Carne Asada Taco')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
    vi.useRealTimers();
  });

  // The scan is paid for and still running server-side; losing the
  // connection must not throw it away and send them back to upload again.
  it('keeps the scan after repeated poll failures and resumes on request', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan.mockRejectedValue(new ScanError('Request failed (429)', null));

    await scanAPhoto();
    expect(await screen.findByText('Reading the menu…')).toBeInTheDocument();
    await vi.advanceTimersByTimeAsync(8000 + 16000 + 32000);

    expect(await screen.findByRole('alert')).toHaveTextContent(/still running/);
    expect(screen.queryByRole('button', { name: 'Scan the menu' })).toBeNull();

    getScan.mockReset();
    getScan.mockResolvedValue(readyScan([dish({})]));
    fireEvent.click(screen.getByRole('button', { name: 'Keep waiting' }));

    expect(await screen.findByText('Carne Asada Taco')).toBeInTheDocument();
    expect(getScan).toHaveBeenCalledWith('scan-1');
    expect(startScan).toHaveBeenCalledTimes(1);
    vi.useRealTimers();
  });

  it('keeps dishes that failed to publish on screen for another try', async () => {
    getScan.mockResolvedValue(
      readyScan([dish({ id: 'd1' }), dish({ id: 'd2', name: 'Pollo Taco' })]),
    );
    acceptScan.mockResolvedValue({
      accepted: [{ id: 'd1', name: 'x' }],
      failed: [{ id: 'd2', name: 'x', error: 'boom' }],
      restaurant_published: true,
      remaining_pending: 1,
    });

    await scanAPhoto();
    fireEvent.click(await screen.findByRole('button', { name: 'Add 2 dishes to the menu' }));

    expect(await screen.findByRole('alert')).toHaveTextContent("Couldn't add Pollo Taco");
    expect(push).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Add 1 dish to the menu' }));
    await waitFor(() => expect(acceptScan).toHaveBeenLastCalledWith('scan-1', ['d2']));
  });

  // A draft restaurant's page 404s until most of its menu is accepted.
  it('stays put with an explanation when the restaurant is not live yet', async () => {
    getScan.mockResolvedValue(readyScan([dish({})]));
    acceptScan.mockResolvedValue({
      accepted: [],
      restaurant_published: false,
      remaining_pending: 3,
    });

    await scanAPhoto();
    fireEvent.click(await screen.findByRole('button', { name: 'Add 1 dish to the menu' }));

    expect(await screen.findByText(/isn.t public yet/)).toBeInTheDocument();
    expect(push).not.toHaveBeenCalled();
  });

  // The name-implied ingredients (a pizza's crust) land after the dishes
  // are reviewable, and only on dishes still pending.
  it('waits for the ingredient pass before offering dishes to publish', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan
      .mockResolvedValueOnce({ ...readyScan([dish({})]), enrichment_status: 'pending' })
      .mockResolvedValueOnce(readyScan([dish({})]));

    await scanAPhoto();
    expect(await screen.findByText('Checking ingredients…')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /to the menu/ })).toBeNull();

    await vi.advanceTimersByTimeAsync(4000);
    expect(
      await screen.findByRole('button', { name: 'Add 1 dish to the menu' }),
    ).toBeInTheDocument();
    vi.useRealTimers();
  });

  it('ticks nothing when the ingredient pass failed', async () => {
    getScan.mockResolvedValue({ ...readyScan([dish({})]), enrichment_status: 'failed' });

    await scanAPhoto();

    expect(await screen.findByText(/couldn.t finish checking ingredients/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add 0 dishes to the menu' })).toBeDisabled();
  });

  it('sends a failed scan back to the start with a next step', async () => {
    getScan.mockResolvedValue({ ...readyScan([]), ready: false, failed: true, status: 'failed' });

    await scanAPhoto();

    expect(await screen.findByRole('alert')).toHaveTextContent(/Try a sharper photo/);
    expect(screen.getByRole('button', { name: 'Scan the menu' })).toBeInTheDocument();
  });

  it("shows the API's sentence when the daily quota is spent", async () => {
    startScan.mockRejectedValue(
      new ScanError(
        'Daily scan limit reached for this account. Try again tomorrow.',
        'quota_exceeded',
      ),
    );

    await scanAPhoto();

    expect(await screen.findByRole('alert')).toHaveTextContent('Daily scan limit reached');
  });

  it('sends a signed-out person to log in and back', async () => {
    uploadAttachment.mockRejectedValue(new NotSignedInError());

    await scanAPhoto();

    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith('/login?next=%2Frestaurants%2Fninis%2Fscan'),
    );
  });
});
