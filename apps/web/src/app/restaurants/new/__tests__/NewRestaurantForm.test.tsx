import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * The form's job is to get a new place into a scan without splitting an
 * existing restaurant in two: a likely duplicate must stop and ask, and
 * only an explicit "add it anyway" sends force.
 */

const mockCreate = vi.fn();
const mockBrand = vi.fn();
vi.mock('../../../../lib/cities', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/cities')>()),
  createRestaurant: (input: unknown) => mockCreate(input),
  brandRestaurant: (slug: string, images: unknown) => mockBrand(slug, images),
}));

vi.mock('../../../../lib/shrink-image', () => ({
  MAX_UPLOAD_BYTES: 4 * 1024 * 1024,
  shrinkForUpload: async (file: File) => file,
  tooLargeToUpload: (file: File) => file.size > 4 * 1024 * 1024,
}));

const mockPush = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: mockPush }) }));

import { NewRestaurantForm } from '../_NewRestaurantForm';
import { NotSignedInError } from '../../../../lib/chat';

const SLC = {
  id: 'c1',
  slug: 'salt-lake-city',
  name: 'Salt Lake City',
  region: 'Utah',
  country: 'US',
};
const DURANGO = { id: 'c2', slug: 'durango', name: 'Durango', region: 'Colorado', country: 'US' };

function fill(name: string) {
  fireEvent.change(screen.getByTestId('new-restaurant-city'), {
    target: { value: 'salt-lake-city' },
  });
  fireEvent.change(screen.getByTestId('new-restaurant-name'), { target: { value: name } });
  fireEvent.submit(screen.getByTestId('new-restaurant-form'));
}

beforeEach(() => {
  mockCreate.mockReset();
  mockBrand.mockReset();
  mockPush.mockReset();
  // jsdom has no object URLs; add the two statics without replacing the
  // URL constructor itself.
  URL.createObjectURL = vi.fn(() => 'blob:preview');
  URL.revokeObjectURL = vi.fn();
});

const created = {
  kind: 'created',
  slug: 'red-iguana',
  web_path: '/restaurants/usa/utah/salt-lake-city/red-iguana',
};

async function pickLogo() {
  const file = new File(['x'], 'logo.png', { type: 'image/png' });
  fireEvent.change(screen.getByTestId('new-restaurant-logo-input'), { target: { files: [file] } });
  await waitFor(() =>
    expect(screen.getByTestId('new-restaurant-logo-preview')).toBeInTheDocument(),
  );
  return file;
}

describe('NewRestaurantForm', () => {
  it('creates the restaurant in the chosen city and goes straight to its scan', async () => {
    mockCreate.mockResolvedValue({
      kind: 'created',
      slug: 'red-iguana',
      web_path: '/restaurants/usa/utah/salt-lake-city/red-iguana',
    });
    render(<NewRestaurantForm cities={[DURANGO, SLC]} />);

    fill('Red Iguana');

    await waitFor(() =>
      expect(mockPush).toHaveBeenCalledWith('/restaurants/usa/utah/salt-lake-city/red-iguana/scan'),
    );
    expect(mockCreate).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Red Iguana', city_slug: 'salt-lake-city', force: false }),
    );
  });

  // The images ride the same branding door the owner uses, after the
  // restaurant exists (its creator may brand it while it is a draft), so
  // the form's job is to send them for the right slug before moving on.
  it('uploads a picked logo for the new restaurant before going to its scan', async () => {
    mockCreate.mockResolvedValue(created);
    mockBrand.mockResolvedValue(undefined);
    render(<NewRestaurantForm cities={[SLC]} />);

    const file = await pickLogo();
    fill('Red Iguana');

    await waitFor(() =>
      expect(mockPush).toHaveBeenCalledWith('/restaurants/usa/utah/salt-lake-city/red-iguana/scan'),
    );
    expect(mockBrand).toHaveBeenCalledWith('red-iguana', { logo: file, banner: null });
  });

  // Two files that each pass the per-file check can exceed the web
  // server's body cap together; they go as two requests, one per image.
  it('uploads the logo and banner separately when together they exceed the body cap', async () => {
    mockCreate.mockResolvedValue(created);
    mockBrand.mockResolvedValue(undefined);
    render(<NewRestaurantForm cities={[SLC]} />);

    const big = (name: string) =>
      new File([new Uint8Array(3 * 1024 * 1024)], name, { type: 'image/jpeg' });
    const logo = big('logo.jpg');
    const banner = big('banner.jpg');
    fireEvent.change(screen.getByTestId('new-restaurant-logo-input'), {
      target: { files: [logo] },
    });
    fireEvent.change(screen.getByTestId('new-restaurant-banner-input'), {
      target: { files: [banner] },
    });
    await waitFor(() =>
      expect(screen.getByTestId('new-restaurant-banner-preview')).toBeInTheDocument(),
    );
    fill('Red Iguana');

    await waitFor(() => expect(mockPush).toHaveBeenCalled());
    expect(mockBrand).toHaveBeenCalledTimes(2);
    expect(mockBrand).toHaveBeenNthCalledWith(1, 'red-iguana', { logo });
    expect(mockBrand).toHaveBeenNthCalledWith(2, 'red-iguana', { banner });
  });

  it('keeps a lapsed session out of the login round trip once the restaurant exists', async () => {
    mockCreate.mockResolvedValue(created);
    mockBrand.mockRejectedValue(new NotSignedInError());
    render(<NewRestaurantForm cities={[SLC]} />);

    await pickLogo();
    fill('Red Iguana');

    await waitFor(() =>
      expect(screen.getByTestId('new-restaurant-branding-failed')).toBeInTheDocument(),
    );
    expect(mockPush).not.toHaveBeenCalled();

    // Enter in a field after the failure goes on to the scan, not back
    // through create.
    fireEvent.submit(screen.getByTestId('new-restaurant-form'));
    await waitFor(() =>
      expect(mockPush).toHaveBeenCalledWith('/restaurants/usa/utah/salt-lake-city/red-iguana/scan'),
    );
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  it('sends nothing to the branding door when no image was picked', async () => {
    mockCreate.mockResolvedValue(created);
    render(<NewRestaurantForm cities={[SLC]} />);

    fill('Red Iguana');

    await waitFor(() => expect(mockPush).toHaveBeenCalled());
    expect(mockBrand).not.toHaveBeenCalled();
  });

  // A retry would trip the duplicate check on the restaurant that now
  // exists, so a failed image save offers the scan instead of an error.
  it('offers the scan link when the restaurant was added but its images did not save', async () => {
    mockCreate.mockResolvedValue(created);
    mockBrand.mockRejectedValue(new Error('too big'));
    render(<NewRestaurantForm cities={[SLC]} />);

    await pickLogo();
    fill('Red Iguana');

    await waitFor(() =>
      expect(screen.getByTestId('new-restaurant-branding-failed')).toBeInTheDocument(),
    );
    expect(screen.getByTestId('new-restaurant-continue')).toHaveAttribute(
      'href',
      '/restaurants/usa/utah/salt-lake-city/red-iguana/scan',
    );
    expect(mockPush).not.toHaveBeenCalled();
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  it('stops on a likely duplicate and only forces after the user says none match', async () => {
    mockCreate.mockResolvedValueOnce({
      kind: 'duplicate',
      candidates: [
        { id: 'r1', slug: 'red-iguana', name: 'Red Iguana', status: 'published', street: null },
      ],
    });
    render(<NewRestaurantForm cities={[DURANGO, SLC]} />);

    fill('Red Iguana 2');

    await screen.findByTestId('new-restaurant-duplicates');
    expect(mockPush).not.toHaveBeenCalled();

    mockCreate.mockResolvedValueOnce({
      kind: 'created',
      slug: 'red-iguana-2',
      web_path: '/restaurants/usa/utah/salt-lake-city/red-iguana-2',
    });
    fireEvent.click(screen.getByTestId('new-restaurant-force'));

    await waitFor(() =>
      expect(mockPush).toHaveBeenCalledWith(
        '/restaurants/usa/utah/salt-lake-city/red-iguana-2/scan',
      ),
    );
    expect(mockCreate).toHaveBeenLastCalledWith(expect.objectContaining({ force: true }));
  });

  // Another user's draft can't be scanned by this user, so linking to its
  // scan would dead-end; it is named, not linked.
  it("names someone else's draft without linking to a scan they can't run", async () => {
    mockCreate.mockResolvedValueOnce({
      kind: 'duplicate',
      candidates: [
        {
          id: 'r1',
          slug: 'red-iguana',
          name: 'Red Iguana',
          status: 'draft',
          street: null,
          scannable: false,
        },
        {
          id: 'r2',
          slug: 'red-iguana-2',
          name: 'Red Iguana 2',
          status: 'draft',
          street: null,
          scannable: true,
        },
      ],
    });
    render(<NewRestaurantForm cities={[DURANGO, SLC]} />);

    fill('Red Iguana');

    const [theirs, mine] = await screen.findAllByTestId('new-restaurant-candidate');
    expect(theirs!.querySelector('a')).toBeNull();
    expect(theirs).toHaveTextContent('someone is already adding this one');
    expect(mine!.querySelector('a')).toHaveAttribute('href', '/restaurants/red-iguana-2/scan');
  });

  it('sends an expired session back to login instead of showing an error', async () => {
    mockCreate.mockRejectedValue(new NotSignedInError());
    render(<NewRestaurantForm cities={[DURANGO, SLC]} />);

    fill('Red Iguana');

    await waitFor(() => expect(mockPush).toHaveBeenCalledWith('/login?next=%2Frestaurants%2Fnew'));
    expect(screen.queryByTestId('new-restaurant-error')).toBeNull();
  });

  // A failed load must not read as "no cities": that would tell someone
  // their city isn't covered when the API just hiccupped.
  it('tells a failed city load apart from an empty list', () => {
    const { unmount } = render(<NewRestaurantForm cities={[]} loadFailed />);
    expect(screen.getByTestId('new-restaurant-load-failed')).toBeInTheDocument();
    expect(screen.queryByTestId('new-restaurant-no-cities')).toBeNull();
    unmount();

    render(<NewRestaurantForm cities={[]} />);
    expect(screen.getByTestId('new-restaurant-no-cities')).toBeInTheDocument();
  });

  // Candidates belong to the name that was submitted; editing it while the
  // check is in flight would let "add anyway" force a different place.
  it('locks the fields while a submit is in flight', async () => {
    let resolve!: (v: unknown) => void;
    mockCreate.mockReturnValue(new Promise((r) => (resolve = r)));
    render(<NewRestaurantForm cities={[DURANGO, SLC]} />);

    fill('Red Iguana');

    expect(screen.getByTestId('new-restaurant-name')).toBeDisabled();
    expect(screen.getByTestId('new-restaurant-city')).toBeDisabled();
    resolve({ kind: 'duplicate', candidates: [] });
    await waitFor(() => expect(screen.getByTestId('new-restaurant-name')).not.toBeDisabled());
  });

  it('preselects the only city when there is just one', () => {
    render(<NewRestaurantForm cities={[SLC]} />);
    expect((screen.getByTestId('new-restaurant-city') as HTMLSelectElement).value).toBe(
      'salt-lake-city',
    );
  });
});
