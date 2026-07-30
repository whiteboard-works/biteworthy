'use client';

import { useEffect, useState } from 'react';
import {
  createErrorCopy,
  createIngredient,
  fetchAdminIngredients,
  type AdminIngredient,
  type AdminIngredientsResponse,
} from '../../../../lib/admin/taxonomy';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { Pagination } from '../../_Pagination';
import { TaxonomyTabs } from '../_TaxonomyTabs';
import { IngredientRow } from './_IngredientRow';

/**
 * /admin/taxonomy/ingredients — the catalog editor. The closed
 * taxonomy is the product's safety backbone, so the page mirrors the
 * server's rails: create requires an existing parent for dotted
 * paths, slug/path render read-only after create, deletes explain
 * what still references the node.
 */

const PAGE_SIZE = 100;
const EMPTY_FORM = { slug: '', name: '', path: '', aliases: '', allergen: false };

export default function AdminIngredientsPage() {
  const [q, setQ] = useState('');
  const [offset, setOffset] = useState(0);
  const [refreshKey, setRefreshKey] = useState(0);
  const [data, setData] = useState<AdminIngredientsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchAdminIngredients({ q: q || undefined, limit: PAGE_SIZE, offset })
      .then((d) => {
        if (!active) return;
        // A delete can strand the offset past the shrunken total.
        if (d.ingredients.length === 0 && offset > 0 && d.pagination.total <= offset) {
          setOffset(0);
          return;
        }
        setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [q, offset, refreshKey]);

  const onUpdated = (updated: AdminIngredient) => {
    setData((prev) =>
      prev
        ? {
            ...prev,
            ingredients: prev.ingredients.map((i) => (i.id === updated.id ? updated : i)),
          }
        : prev,
    );
  };

  const onCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    try {
      await createIngredient({
        slug: form.slug.trim(),
        name: form.name.trim(),
        path: form.path.trim(),
        aliases: form.aliases.split(',').map((a) => a.trim()).filter(Boolean),
        allergen: form.allergen,
      });
      setForm(EMPTY_FORM);
      setRefreshKey((k) => k + 1);
    } catch (err) {
      setCreateError(createErrorCopy(err));
    } finally {
      setCreating(false);
    }
  };

  return (
    <main data-testid="admin-ingredients">
      <div className="flex flex-wrap items-center justify-between gap-bw-3">
        <h1 className="text-bw-2xl font-bold text-zinc-900">Taxonomy</h1>
        <TaxonomyTabs />
      </div>

      <form
        onSubmit={(e) => void onCreate(e)}
        data-testid="ingredient-create-form"
        className="mt-bw-4 grid gap-bw-2 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-3 text-bw-sm sm:grid-cols-5"
      >
        <input
          value={form.slug}
          onChange={(e) => setForm({ ...form, slug: e.target.value })}
          placeholder="slug (dairy-kefir)"
          required
          data-testid="ingredient-new-slug"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <input
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="Name"
          required
          data-testid="ingredient-new-name"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <input
          value={form.path}
          onChange={(e) => setForm({ ...form, path: e.target.value })}
          placeholder="path (dairy.kefir)"
          required
          data-testid="ingredient-new-path"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <input
          value={form.aliases}
          onChange={(e) => setForm({ ...form, aliases: e.target.value })}
          placeholder="aliases, comma-sep"
          data-testid="ingredient-new-aliases"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <div className="flex items-center justify-between gap-bw-2">
          <label className="flex items-center gap-bw-1 text-zinc-600">
            <input
              type="checkbox"
              checked={form.allergen}
              onChange={(e) => setForm({ ...form, allergen: e.target.checked })}
              data-testid="ingredient-new-allergen"
            />
            allergen
          </label>
          <button
            type="submit"
            disabled={creating}
            data-testid="ingredient-create"
            className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
          >
            {creating ? 'Adding…' : 'Add'}
          </button>
        </div>
        {createError && (
          <p role="alert" data-testid="ingredient-create-error" className="text-red-700 sm:col-span-5">
            {createError}
          </p>
        )}
      </form>

      <input
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          setOffset(0);
        }}
        placeholder="Search name or alias…"
        data-testid="ingredient-search"
        className="mt-bw-4 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-sm"
      />

      {error && (
        <div role="alert" data-testid="ingredients-error" className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900">
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading taxonomy…
        </p>
      )}

      {data && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-2">
            {data.ingredients.map((ingredient) => (
              <IngredientRow
                key={ingredient.id}
                ingredient={ingredient}
                onUpdated={onUpdated}
                onDeleted={() => setRefreshKey((k) => k + 1)}
              />
            ))}
          </ul>
          <Pagination
            total={data.pagination.total}
            limit={data.pagination.limit}
            offset={data.pagination.offset}
            onOffset={setOffset}
          />
        </div>
      )}
    </main>
  );
}
