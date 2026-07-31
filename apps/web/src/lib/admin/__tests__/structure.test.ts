import { describe, expect, it, vi } from 'vitest';
import { deleteSection, saveAddress, saveHours, structureErrorCopy } from '../structure';
import { AdminError } from '../shared';

/**
 * The structure fetchers own the only PUT in the admin layer. Two
 * things matter here and nowhere else:
 *   - address and hours are WHOLESALE replaces, so the verb and body
 *     have to be right or a save lands half-applied;
 *   - deleting a section returns how many dishes were KEPT, which is
 *     the reassurance the UI shows an admin mid-restructure.
 */

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('saveHours / saveAddress', () => {
  it('PUTs the whole week as JSON', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse({ address: null, hours: [] }));

    await saveHours('r1', [{ day_of_week: 1, opens_at: '11:00', closes_at: '21:00' }], fetchImpl);

    const [path, init] = fetchImpl.mock.calls[0]!;
    expect(path).toBe('/api/admin/restaurants/r1/hours');
    expect(init.method).toBe('PUT');
    expect(init.headers).toMatchObject({ 'Content-Type': 'application/json' });
    expect(JSON.parse(init.body)).toEqual({
      hours: [{ day_of_week: 1, opens_at: '11:00', closes_at: '21:00' }],
    });
  });

  it('PUTs the address and surfaces a refusal as an AdminError', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse({ error: 'invalid_coordinate', field: 'latitude' }, 422));

    await expect(saveAddress('r1', { street: '1 Elm' }, fetchImpl)).rejects.toMatchObject({
      status: 422,
      code: 'invalid_coordinate',
    });
  });
});

describe('deleteSection', () => {
  // The count is the whole point: an admin needs to see the dishes survived.
  it('resolves with the number of dishes left unsectioned', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse({ deleted: true, items_unsectioned: 3 }));

    await expect(deleteSection('s1', fetchImpl)).resolves.toBe(3);
    expect(fetchImpl.mock.calls[0]![1].method).toBe('DELETE');
  });

  it('defaults to 0 when the server omits the count', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse({ deleted: true }));
    await expect(deleteSection('s1', fetchImpl)).resolves.toBe(0);
  });
});

describe('structureErrorCopy', () => {
  const copy = (body: Record<string, unknown>) =>
    structureErrorCopy(new AdminError('nope', 422, String(body.error), body));

  it('names the offending values so the admin knows which field to fix', () => {
    expect(copy({ error: 'invalid_day_of_week', values: ['monday'] })).toContain('monday');
    expect(copy({ error: 'invalid_time_of_day', values: ['25:99'] })).toContain('25:99');
    expect(copy({ error: 'invalid_coordinate', field: 'latitude' })).toContain('latitude');
  });

  it('covers every structured refusal the structure endpoints emit', () => {
    for (const error of [
      'closed_day_has_hours',
      'hour_rows_must_be_objects',
      'hours_must_be_an_array',
      'invalid_name',
      'invalid_position',
    ]) {
      expect(copy({ error })).toBeTruthy();
    }
  });

  it('declines anything it does not recognize, so the shared copy takes over', () => {
    expect(copy({ error: 'something_else' })).toBeNull();
    expect(structureErrorCopy(new Error('boom'))).toBeNull();
  });
});
