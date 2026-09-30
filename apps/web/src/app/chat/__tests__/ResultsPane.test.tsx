import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import type { ChatPane } from '../../../lib/chat';
import type { RestaurantItem } from '../../../lib/restaurants';
import type { ScanStatus } from '../../../lib/scans';

/**
 * The pane draws the site's own rendering of what a tool touched, fetched
 * from the REST endpoints — never the model-facing payload. These pin
 * that it asks for the menu the tool actually read (same preset, same
 * strictness), swaps when the reference changes, and stays honest about
 * hidden dishes.
 */

const fetchRestaurantItemsClient = vi.fn();
const getScan = vi.fn();

vi.mock('../../../lib/restaurants', async () => {
  const actual = await vi.importActual<typeof import('../../../lib/restaurants')>(
    '../../../lib/restaurants',
  );
  return {
    ...actual,
    fetchRestaurantItemsClient: (slug: string, opts: unknown) =>
      fetchRestaurantItemsClient(slug, opts),
  };
});
vi.mock('../../../lib/scans', async () => {
  const actual = await vi.importActual<typeof import('../../../lib/scans')>('../../../lib/scans');
  return { ...actual, getScan: (id: string) => getScan(id) };
});
vi.mock('../../_PostHogProvider', () => ({ useTracker: () => ({ track: vi.fn() }) }));

const { ResultsPane } = await import('../_ResultsPane');

const item = (over: Partial<RestaurantItem>): RestaurantItem => ({
  id: 'i-1',
  restaurant_id: 'r-1',
  name: 'Pad Thai',
  description: '',
  confidence: 'confirmed',
  ingredient_ids: [],
  tag_ids: [],
  menu_section_id: null,
  menu_section_name: null,
  status: 'visible',
  reasons: [],
  photo_url: null,
  ...over,
});

const menu = {
  restaurant_id: 'r-1',
  filter: {
    source: 'preset' as const,
    preset_slug: 'vegan',
    strictness: 'balanced' as const,
    avoid_ingredient_ids: [],
    avoid_tag_ids: [],
  },
  items: [
    item({ id: 'i-1', name: 'Pad Thai', menu_section_id: 's-1', menu_section_name: 'Mains' }),
    item({
      id: 'i-2',
      name: 'Queso',
      menu_section_id: 's-1',
      menu_section_name: 'Mains',
      status: 'hidden',
      reasons: [
        {
          kind: 'avoid_ingredient',
          ingredient_id: 'g-1',
          ingredient_name: 'Cheddar',
          ingredient_family: 'dairy',
        },
      ],
    }),
  ],
};

const scan: ScanStatus = {
  scan_id: 'run-1',
  status: 'staged',
  ready: true,
  failed: false,
  restaurant_id: 'r-1',
  restaurant_slug: 'ninis',
  restaurant_published: true,
  dish_count: 2,
  pending_count: 1,
  accepted_count: 1,
  rejected_count: 0,
  dishes: [
    {
      id: 'd-1',
      name: 'Carnitas',
      section: 'Tacos',
      decision: 'pending',
      prices: [],
      ingredients: ['pork', 'onion'],
      tags: [],
      unresolved: { ingredients: [], tags: [] },
      needs_attention: false,
    },
    {
      id: 'd-2',
      name: 'Queso',
      section: 'Sides',
      decision: 'accepted',
      prices: [],
      ingredients: [],
      tags: [],
      unresolved: { ingredients: ['crema'], tags: [] },
      needs_attention: true,
    },
  ],
};

beforeEach(() => {
  fetchRestaurantItemsClient.mockResolvedValue(menu);
  getScan.mockResolvedValue(scan);
});

afterEach(() => {
  vi.clearAllMocks();
});

describe('ResultsPane', () => {
  it('says what it is for while nothing has been acted on', () => {
    render(<ResultsPane pane={null} working={null} />);

    expect(screen.getByTestId('pane-empty')).toBeInTheDocument();
    expect(fetchRestaurantItemsClient).not.toHaveBeenCalled();
  });

  it('fetches the menu the tool read — same preset, same strictness — and shows hidden dishes with their reason', async () => {
    const pane: ChatPane = {
      kind: 'menu',
      restaurant: 'ninis',
      preset: 'vegan',
      strictness: 'strict',
    };
    render(<ResultsPane pane={pane} working={null} />);

    await screen.findByTestId('pane-menu');
    expect(fetchRestaurantItemsClient).toHaveBeenCalledWith('ninis', {
      signedIn: true,
      presetSlug: 'vegan',
      strictness: 'strict',
    });
    expect(screen.getByText('Mains')).toBeInTheDocument();
    // The dish page must judge under the same filter — preset and the
    // assistant's strictness override both ride on the link.
    expect(screen.getByRole('link', { name: 'Pad Thai' })).toHaveAttribute(
      'href',
      '/restaurants/ninis/items/i-1?profile=vegan&strictness=strict',
    );
    // The hidden dish is drawn, not dropped, and says why.
    expect(screen.getByRole('link', { name: 'Queso' })).toBeInTheDocument();
    expect(screen.getByTestId('chip-avoid_ingredient')).toBeInTheDocument();
  });

  it('shows the scan with each dish where the review left it', async () => {
    render(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} working={null} />);

    await screen.findByTestId('pane-scan');
    expect(getScan).toHaveBeenCalledWith('run-1');
    expect(screen.getByText('Carnitas')).toBeInTheDocument();
    expect(screen.getByText('pork, onion')).toBeInTheDocument();
    expect(screen.getByText('On the menu')).toBeInTheDocument();
    expect(screen.getByText('Needs a look')).toBeInTheDocument();
    expect(screen.getByText(/Scan · ninis/)).toBeInTheDocument();
  });

  it('keeps looking at a scan that is still extracting', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan
      .mockResolvedValueOnce({ ...scan, status: 'extracting', ready: false, dishes: undefined })
      .mockResolvedValueOnce(scan);
    render(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} working={null} />);

    expect(await screen.findByText(/usually 20 to 60 seconds/)).toBeInTheDocument();
    await vi.advanceTimersByTimeAsync(4000);
    await waitFor(() => expect(getScan).toHaveBeenCalledTimes(2));
    expect(await screen.findByText('Carnitas')).toBeInTheDocument();
    vi.useRealTimers();
  });

  it('swaps when the reference changes and ignores the same one twice', async () => {
    const { rerender } = render(
      <ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} working={null} />,
    );
    await screen.findByTestId('pane-menu');

    rerender(<ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} working={null} />);
    expect(fetchRestaurantItemsClient).toHaveBeenCalledTimes(1);

    rerender(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} working={null} />);
    await screen.findByTestId('pane-scan');
    expect(screen.queryByTestId('pane-menu')).not.toBeInTheDocument();
  });

  // An accept on a staged scan points at the very same reference as the
  // listing before it; only the event can say the dishes changed.
  it('looks again at the same reference when the revision moves', async () => {
    getScan.mockResolvedValueOnce(scan).mockResolvedValueOnce({
      ...scan,
      pending_count: 0,
      accepted_count: 2,
      dishes: scan.dishes!.map((d) => ({ ...d, decision: 'accepted' as const })),
    });
    const { rerender } = render(
      <ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} revision={1} working={null} />,
    );
    expect(await screen.findByText(/1 to review/)).toBeInTheDocument();

    rerender(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} revision={2} working={null} />);

    expect(await screen.findByText(/0 to review · 2 on the menu/)).toBeInTheDocument();
    expect(getScan).toHaveBeenCalledTimes(2);
  });

  // After an avoid-list change the loop re-points the pane at the same
  // menu. The labels on screen are the ones that change just made wrong,
  // so they come down until the new answer is in — and stay down if it
  // never comes.
  it('takes the old menu down while the same reference is fetched again, and keeps it down on failure', async () => {
    let rejectB: (e: Error) => void = () => {};
    fetchRestaurantItemsClient
      .mockResolvedValueOnce(menu)
      .mockImplementationOnce(() => new Promise((_r, rej) => (rejectB = rej)));
    const { rerender } = render(
      <ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} revision={1} working={null} />,
    );
    expect(await screen.findByRole('link', { name: 'Pad Thai' })).toBeInTheDocument();

    rerender(
      <ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} revision={2} working={null} />,
    );
    expect(screen.queryByRole('link', { name: 'Pad Thai' })).not.toBeInTheDocument();

    rejectB(new Error('Request failed (502)'));
    expect(await screen.findByRole('alert')).toHaveTextContent('502');
    expect(screen.queryByRole('link', { name: 'Pad Thai' })).not.toBeInTheDocument();
  });

  it('reads a stored pane with its keys in another order as the same one', async () => {
    const { rerender } = render(
      <ResultsPane
        pane={{ kind: 'menu', restaurant: 'ninis', preset: 'vegan' }}
        revision={1}
        working={null}
      />,
    );
    await screen.findByTestId('pane-menu');

    // What `jsonb` hands back: same fields, different order, nulls for the rest.
    rerender(
      <ResultsPane
        pane={{ preset: 'vegan', restaurant: 'ninis', kind: 'menu', scan_id: null }}
        revision={1}
        working={null}
      />,
    );
    expect(fetchRestaurantItemsClient).toHaveBeenCalledTimes(1);
    expect(screen.getByTestId('pane-menu')).toBeInTheDocument();
  });

  it('does not draw the old menu under the new pane while it loads', async () => {
    let resolveB: (v: typeof menu) => void = () => {};
    fetchRestaurantItemsClient
      .mockResolvedValueOnce(menu)
      .mockImplementationOnce(() => new Promise((r) => (resolveB = r)));
    const { rerender } = render(
      <ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} working={null} />,
    );
    await screen.findByTestId('pane-menu');

    rerender(<ResultsPane pane={{ kind: 'menu', restaurant: 'zia' }} working={null} />);
    // Menu A's dishes would carry B's slug in every link; nothing is drawn instead.
    expect(screen.queryByTestId('pane-menu')).not.toBeInTheDocument();
    expect(screen.getByText(/Menu · zia/)).toBeInTheDocument();

    resolveB({ ...menu, items: [item({ id: 'z-1', name: 'Zia Bowl' })] });
    expect(await screen.findByRole('link', { name: 'Zia Bowl' })).toHaveAttribute(
      'href',
      '/restaurants/zia/items/z-1?profile=vegan',
    );
  });

  it('keeps polling a scan through one failed look', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan
      .mockResolvedValueOnce({ ...scan, status: 'extracting', ready: false, dishes: undefined })
      .mockRejectedValueOnce(new Error('Request failed (502)'))
      .mockResolvedValueOnce(scan);
    render(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} working={null} />);

    await screen.findByText(/usually 20 to 60 seconds/);
    await vi.advanceTimersByTimeAsync(4000);
    expect(await screen.findByRole('alert')).toHaveTextContent('502');
    // A failed look waits twice as long before the next.
    await vi.advanceTimersByTimeAsync(8000);
    expect(await screen.findByText('Carnitas')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    vi.useRealTimers();
  });

  // A chat reopened mid-scan gets no further pane event, so the first
  // look has to be retried on its own.
  it('retries a scan whose very first look fails, and gives up after enough in a row', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    getScan.mockRejectedValueOnce(new Error('Request failed (429)')).mockResolvedValueOnce(scan);
    render(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-1' }} working={null} />);

    expect(await screen.findByRole('alert')).toHaveTextContent('429');
    await vi.advanceTimersByTimeAsync(8000);
    expect(await screen.findByText('Carnitas')).toBeInTheDocument();
    expect(getScan).toHaveBeenCalledTimes(2);

    // Once it has answered ready there is nothing left to watch.
    await vi.advanceTimersByTimeAsync(64000);
    expect(getScan).toHaveBeenCalledTimes(2);

    getScan.mockReset();
    getScan.mockRejectedValue(new Error('Request failed (404)'));
    render(<ResultsPane pane={{ kind: 'scan', scan_id: 'run-gone' }} working={null} />);
    // Retries back off: 4s, 8s, 16s, 32s, 64s — the first look plus
    // MAX_FAILED_LOOKS retries, then it stops asking.
    for (const wait of [4000, 8000, 16000, 32000, 64000, 128000]) {
      await vi.advanceTimersByTimeAsync(wait);
    }
    expect(getScan).toHaveBeenCalledTimes(6);
    vi.useRealTimers();
  });

  it('opens a dish in a new tab so the chat beside it is not abandoned', async () => {
    render(<ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} working={null} />);

    expect(await screen.findByRole('link', { name: 'Pad Thai' })).toHaveAttribute(
      'target',
      '_blank',
    );
  });

  it('stops saying “Updating…” when the chat goes blank mid-fetch', async () => {
    fetchRestaurantItemsClient.mockImplementationOnce(() => new Promise(() => {}));
    const { rerender } = render(
      <ResultsPane pane={{ kind: 'menu', restaurant: 'ninis' }} working={null} />,
    );
    expect(await screen.findByText('Updating…')).toBeInTheDocument();

    rerender(<ResultsPane pane={null} working={null} />);

    expect(screen.queryByText('Updating…')).not.toBeInTheDocument();
    expect(screen.getByTestId('pane-empty')).toBeInTheDocument();
  });

  it('shows the running tool’s sentence', () => {
    render(<ResultsPane pane={null} working="Reading the menu at ninis" />);

    expect(screen.getByTestId('pane-working')).toHaveTextContent('Reading the menu at ninis…');
  });

  it('reports a failed fetch instead of a blank pane', async () => {
    fetchRestaurantItemsClient.mockRejectedValue(new Error('Restaurant not found'));
    render(<ResultsPane pane={{ kind: 'menu', restaurant: 'gone' }} working={null} />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Restaurant not found');
  });
});
