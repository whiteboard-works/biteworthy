import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { AdminError } from '../../../../lib/admin/shared';

/**
 * A second spelling of a city we cover splits its restaurants across two
 * pages, so a duplicate must come back as "already covered as …", naming
 * the existing slug, rather than a generic failure.
 */

const mockCreate = vi.fn();
vi.mock('../../../../lib/cities', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/cities')>()),
  createCity: (input: unknown) => mockCreate(input),
}));

const mockRefresh = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: mockRefresh }) }));

import { CityCreateForm } from '../_CityCreateForm';

function submit(name: string, region: string) {
  fireEvent.change(screen.getByTestId('city-new-name'), { target: { value: name } });
  fireEvent.change(screen.getByTestId('city-new-region'), { target: { value: region } });
  fireEvent.submit(screen.getByTestId('city-create-form'));
}

beforeEach(() => {
  mockCreate.mockReset();
  mockRefresh.mockReset();
});

describe('CityCreateForm', () => {
  it('creates the city and refreshes the list', async () => {
    mockCreate.mockResolvedValue({ id: 'c1', slug: 'salt-lake-city' });
    render(<CityCreateForm />);

    submit(' Salt Lake City ', 'ut');

    await waitFor(() => expect(mockRefresh).toHaveBeenCalled());
    expect(mockCreate).toHaveBeenCalledWith({ name: 'Salt Lake City', region: 'ut' });
  });

  it('names the existing city on a duplicate', async () => {
    mockCreate.mockRejectedValue(
      new AdminError('dup', 409, 'city_exists', {
        error: 'city_exists',
        city: { name: 'Salt Lake City', slug: 'salt-lake-city' },
      }),
    );
    render(<CityCreateForm />);

    submit('Salt Lake City', 'UT');

    expect(await screen.findByTestId('city-create-error')).toHaveTextContent(
      'Already covered as Salt Lake City (salt-lake-city).',
    );
    expect(mockRefresh).not.toHaveBeenCalled();
  });
});
