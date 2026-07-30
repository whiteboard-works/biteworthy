import { describe, expect, it, vi } from 'vitest';

/**
 * The taxonomy fetchers must never SEND immutable fields on update
 * (the server 422s them — the lib's type signature is the first
 * line of defense), and a 409 delete refusal must surface its
 * reference counts so the row can explain itself.
 */
import { AdminError } from '../shared';
import {
  createIngredient,
  deleteIngredient,
  deleteRefusalCounts,
  updateIngredient,
} from '../taxonomy';

function ok(body: unknown, status = 200) {
  return vi.fn().mockResolvedValue({ ok: status < 400, status, json: async () => body });
}

describe('admin taxonomy lib', () => {
  it('creates with the full field set and updates with only mutable fields', async () => {
    const impl = ok({ id: 'i1' });
    await createIngredient(
      { slug: 'dairy-kefir', name: 'Kefir', path: 'dairy.kefir', aliases: ['kephir'], allergen: true },
      impl as unknown as typeof fetch,
    );
    expect(impl.mock.calls[0]![0]).toBe('/api/admin/ingredients');

    const patchImpl = ok({ id: 'i1' });
    await updateIngredient('i1', { name: 'Kefir!', allergen: false }, patchImpl as unknown as typeof fetch);
    const [url, init] = patchImpl.mock.calls[0]! as [string, { method: string; body: string }];
    expect(url).toBe('/api/admin/ingredients/i1');
    expect(init.method).toBe('PATCH');
    expect(Object.keys(JSON.parse(init.body))).not.toContain('slug');
    expect(Object.keys(JSON.parse(init.body))).not.toContain('path');
  });

  it('delete resolves on 204 and exposes 409 reference counts', async () => {
    const impl = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    await expect(deleteIngredient('i1', impl as unknown as typeof fetch)).resolves.toBeUndefined();

    const refused = vi.fn().mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({ error: 'in_use', references: { descendants: 0, items: 3, presets: 0, modifiers: 0, profiles: 1 } }),
    });
    const err = await deleteIngredient('i1', refused as unknown as typeof fetch).catch(
      (e: unknown) => e,
    );
    expect(err).toBeInstanceOf(AdminError);
    expect(deleteRefusalCounts(err)).toEqual({
      descendants: 0,
      items: 3,
      presets: 0,
      modifiers: 0,
      profiles: 1,
    });
    expect(deleteRefusalCounts(new Error('x'))).toBeNull();
  });
});
