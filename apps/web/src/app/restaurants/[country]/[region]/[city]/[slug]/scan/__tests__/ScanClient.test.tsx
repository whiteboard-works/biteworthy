import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ScanDish } from '../../../../../../../../lib/scans';

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

const track = vi.fn();
vi.mock('../../../../../../../_PostHogProvider', () => ({ useTracker: () => ({ track }) }));

const uploadAttachment = vi.fn();
const startScan = vi.fn();
const getScan = vi.fn();
const acceptScan = vi.fn();
const rejectScan = vi.fn();

vi.mock('../../../../../../../../lib/scans', async () => {
  const actual = await vi.importActual<typeof import('../../../../../../../../lib/scans')>(
    '../../../../../../../../lib/scans',
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
const { NotSignedInError, ScanError } = await import('../../../../../../../../lib/scans');

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
  restaurant_slug: 'ninis',
  restaurant_published: true,
  dish_count: dishes.length,
  pending_count: dishes.length,
  accepted_count: 0,
  rejected_count: 0,
  enrichment_status: 'completed',
  dishes,
});

async function scanAPhoto() {
  render(
    <ScanClient
      slug="ninis"
      basePath="/restaurants/usa/colorado/durango/ninis"
      restaurantName="Nini's"
    />,
  );
  const file = new File(['x'], 'menu.jpg', { type: 'image/jpeg' });
  fireEvent.change(screen.getByLabelText('Menu photos'), { target: { files: [file] } });
  fireEvent.click(screen.getByRole('button', { name: 'Scan the menu' }));
}

describe('ScanClient', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessionStorage.clear();
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
    await waitFor(() =>
      expect(push).toHaveBeenCalledWith('/restaurants/usa/colorado/durango/ninis'),
    );
  });

  // Counts only: which dishes someone kept or discarded is theirs.
  it('reports the scan funnel with counts and never dish names', async () => {
    getScan.mockResolvedValue(
      readyScan([
        dish({ id: 'd1' }),
        dish({ id: 'd2', name: 'Junk' }),
        dish({ id: 'd3', name: 'Stew', ingredients: [], needs_attention: true }),
        dish({
          id: 'd4',
          name: 'Taco Update',
          updates_existing_item: { item_id: 'i1', name: 'Taco', no_changes: false, diff: {} },
        }),
      ]),
    );
    acceptScan.mockResolvedValue({
      accepted: [],
      restaurant_published: true,
      remaining_pending: 1,
    });

    await scanAPhoto();
    fireEvent.click(await screen.findByLabelText('Junk'));
    fireEvent.click(screen.getByRole('button', { name: 'Add 1 dish to the menu' }));
    await waitFor(() => expect(push).toHaveBeenCalled());

    expect(track).toHaveBeenCalledWith('scan_started', {
      restaurant_slug: 'ninis',
      source: 'photo',
      file_count: 1,
    });
    expect(track).toHaveBeenCalledWith(
      'scan_ready',
      expect.objectContaining({
        restaurant_slug: 'ninis',
        dish_count: 4,
        flagged_count: 2,
        enrichment_failed: false,
      }),
    );
    expect(track).toHaveBeenCalledWith('scan_published', {
      restaurant_slug: 'ninis',
      accepted_count: 1,
      discarded_count: 1,
      restaurant_published: true,
    });
    expect(JSON.stringify(track.mock.calls)).not.toMatch(/Junk|Carne|Stew|Taco/);
  });

  // Discarding a page of a live restaurant's menu doesn't make it private.
  it('reports an all-discarded scan of a public restaurant as still public', async () => {
    getScan.mockResolvedValue({
      ...readyScan([dish({ id: 'd1', name: 'Page Header' })]),
      restaurant_published: true,
    });

    render(
      <ScanClient
        slug="ninis"
        basePath="/restaurants/usa/colorado/durango/ninis"
        restaurantName="Nini's"
      />,
    );
    const file = new File(['x'], 'menu.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByLabelText('Menu photos'), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: 'Scan the menu' }));
    fireEvent.click(await screen.findByLabelText('Page Header'));
    fireEvent.click(screen.getByRole('button', { name: 'Discard 1 dish' }));

    await waitFor(() =>
      expect(track).toHaveBeenCalledWith(
        'scan_published',
        expect.objectContaining({ accepted_count: 0, restaurant_published: true }),
      ),
    );
  });

  // The run can say "published" for an archived restaurant; the live
  // state decides where to send them.
  it('stays put after a recovered accept on a restaurant that is not public', async () => {
    getScan.mockResolvedValueOnce(readyScan([dish({ id: 'd1' })])).mockResolvedValueOnce({
      ...readyScan([dish({ id: 'd1', decision: 'accepted' })]),
      status: 'published',
      restaurant_published: false,
    });
    acceptScan.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    await scanAPhoto();
    fireEvent.click(await screen.findByRole('button', { name: 'Add 1 dish to the menu' }));

    expect(await screen.findByText('Saved.')).toBeInTheDocument();
    expect(push).not.toHaveBeenCalled();
  });

  it('does not treat a dish rejected elsewhere as a recovered accept', async () => {
    getScan
      .mockResolvedValueOnce(readyScan([dish({ id: 'd1' })]))
      .mockResolvedValueOnce(readyScan([dish({ id: 'd1', decision: 'rejected' })]));
    acceptScan.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    await scanAPhoto();
    fireEvent.click(await screen.findByRole('button', { name: 'Add 1 dish to the menu' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Failed to fetch');
    expect(track).not.toHaveBeenCalledWith('scan_published', expect.anything());
    expect(push).not.toHaveBeenCalled();
  });

  it('does not call it done when the discard failed, even if the accept landed elsewhere', async () => {
    getScan
      .mockResolvedValueOnce(readyScan([dish({ id: 'd1' }), dish({ id: 'd2', name: 'Junk' })]))
      .mockResolvedValueOnce(
        readyScan([dish({ id: 'd1', decision: 'accepted' }), dish({ id: 'd2', name: 'Junk' })]),
      );
    rejectScan.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    await scanAPhoto();
    fireEvent.click(await screen.findByLabelText('Junk'));
    fireEvent.click(screen.getByRole('button', { name: 'Add 1 dish to the menu' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Failed to fetch');
    expect(track).not.toHaveBeenCalledWith('scan_published', expect.anything());
  });

  it('reports nothing for a discard when the live status cannot be read', async () => {
    getScan
      .mockResolvedValueOnce(readyScan([dish({ id: 'd1', name: 'Page Header' })]))
      .mockRejectedValueOnce(new TypeError('Failed to fetch'));

    await scanAPhoto();
    fireEvent.click(await screen.findByLabelText('Page Header'));
    fireEvent.click(screen.getByRole('button', { name: 'Discard 1 dish' }));

    expect(await screen.findByText(/Nothing was added/)).toBeInTheDocument();
    expect(track).not.toHaveBeenCalledWith('scan_published', expect.anything());
  });

  // A public restaurant's new run can stay "staged"; the restaurant is still public.
  it('reports a recovered accept on a public restaurant as public', async () => {
    getScan.mockResolvedValueOnce(readyScan([dish({ id: 'd1' })])).mockResolvedValueOnce({
      ...readyScan([dish({ id: 'd1', decision: 'accepted' })]),
      status: 'staged',
      restaurant_published: true,
    });
    acceptScan.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    render(
      <ScanClient
        slug="ninis"
        basePath="/restaurants/usa/colorado/durango/ninis"
        restaurantName="Nini's"
      />,
    );
    const file = new File(['x'], 'menu.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByLabelText('Menu photos'), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: 'Scan the menu' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Add 1 dish to the menu' }));

    await waitFor(() =>
      expect(track).toHaveBeenCalledWith(
        'scan_published',
        expect.objectContaining({ accepted_count: 1, restaurant_published: true }),
      ),
    );
  });

  it('does not report a resumed scan as ready again after a refresh', async () => {
    getScan.mockResolvedValue(readyScan([dish({})]));
    sessionStorage.setItem(
      'bw_scan_scan-9',
      JSON.stringify({ startedAt: Date.now(), ready: true }),
    );

    render(
      <ScanClient
        slug="ninis"
        restaurantName="Nini's"
        basePath="/restaurants/usa/colorado/durango/ninis"
        resumeScanId="scan-9"
      />,
    );
    expect(await screen.findByText('Carne Asada Taco')).toBeInTheDocument();

    expect(track).not.toHaveBeenCalledWith('scan_ready', expect.anything());
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
    render(
      <ScanClient
        slug="ninis"
        basePath="/restaurants/usa/colorado/durango/ninis"
        restaurantName="Nini's"
      />,
    );
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

    await waitFor(() =>
      expect(push).toHaveBeenCalledWith('/restaurants/usa/colorado/durango/ninis'),
    );
    expect(screen.queryByRole('alert')).toBeNull();
    // It did publish, so the funnel must count it.
    expect(track).toHaveBeenCalledWith(
      'scan_published',
      expect.objectContaining({ accepted_count: 1, restaurant_published: true }),
    );
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

  // `failed` is final: the server only says it once the retries are spent.
  it('ticks nothing when the ingredient pass has failed for good', async () => {
    getScan.mockResolvedValue({ ...readyScan([dish({})]), enrichment_status: 'failed' });

    await scanAPhoto();

    expect(await screen.findByText(/couldn.t finish checking ingredients/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add 0 dishes to the menu' })).toBeDisabled();
  });

  // A refresh or an evicted phone tab must not strand a paid scan.
  it('puts the running scan in the URL and resumes it from there', async () => {
    getScan.mockResolvedValue(readyScan([dish({})]));

    await scanAPhoto();
    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith(
        '/restaurants/usa/colorado/durango/ninis/scan?scan=scan-1',
      ),
    );
  });

  it('resumes polling a scan named in the URL without starting a new one', async () => {
    getScan.mockResolvedValue(readyScan([dish({})]));

    render(
      <ScanClient
        slug="ninis"
        restaurantName="Nini's"
        basePath="/restaurants/usa/colorado/durango/ninis"
        resumeScanId="scan-9"
      />,
    );

    expect(await screen.findByText('Carne Asada Taco')).toBeInTheDocument();
    expect(getScan).toHaveBeenCalledWith('scan-9');
    expect(startScan).not.toHaveBeenCalled();
  });

  // The server keeps the pass `pending` through its retries, which can run
  // well past the five minutes allowed for reading the menu.
  it('keeps waiting on a slow ingredient pass after the menu is read', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan.mockResolvedValue({ ...readyScan([dish({})]), enrichment_status: 'pending' });

    await scanAPhoto();
    expect(await screen.findByText('Checking ingredients…')).toBeInTheDocument();
    await vi.advanceTimersByTimeAsync(6 * 60 * 1000);

    expect(screen.getByText('Checking ingredients…')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
    vi.useRealTimers();
  });

  // Holds for drafts too, whose public lookup fails and gives no id.
  it('refuses to resume a scan that belongs to a different restaurant', async () => {
    getScan.mockResolvedValue({
      ...readyScan([dish({})]),
      restaurant_id: 'other',
      restaurant_slug: 'someone-else',
    });

    render(
      <ScanClient
        slug="ninis"
        restaurantName="ninis"
        basePath="/restaurants/usa/colorado/durango/ninis"
        resumeScanId="scan-9"
      />,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('different restaurant');
    expect(screen.queryByText('Carne Asada Taco')).toBeNull();
  });

  it('clears the finished scan from the URL so a refresh starts fresh', async () => {
    getScan.mockResolvedValue(readyScan([dish({ id: 'd1', name: 'Page Header' })]));

    await scanAPhoto();
    fireEvent.click(await screen.findByLabelText('Page Header'));
    fireEvent.click(screen.getByRole('button', { name: 'Discard 1 dish' }));

    expect(await screen.findByText(/Nothing was added/)).toBeInTheDocument();
    expect(replace).toHaveBeenLastCalledWith('/restaurants/usa/colorado/durango/ninis/scan');
  });

  it('offers a fresh scan when a resumed scan has nothing left to decide', async () => {
    getScan.mockResolvedValue(readyScan([dish({ decision: 'accepted' })]));

    render(
      <ScanClient
        slug="ninis"
        restaurantName="Nini's"
        basePath="/restaurants/usa/colorado/durango/ninis"
        resumeScanId="scan-9"
      />,
    );
    fireEvent.click(await screen.findByRole('button', { name: 'Scan another page' }));

    expect(screen.getByRole('button', { name: 'Scan the menu' })).toBeInTheDocument();
    expect(replace).toHaveBeenCalledWith('/restaurants/usa/colorado/durango/ninis/scan');
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
      expect(replace).toHaveBeenCalledWith(
        '/login?next=%2Frestaurants%2Fusa%2Fcolorado%2Fdurango%2Fninis%2Fscan',
      ),
    );
  });
});
