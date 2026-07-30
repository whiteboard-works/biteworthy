'use client';

import { useEffect, useState } from 'react';
import {
  createTag,
  deleteRefusalCounts,
  deleteTag,
  fetchAdminTags,
  updateTag,
  type AdminTag,
  type AdminTagsResponse,
} from '../../../../lib/admin/taxonomy';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { ConfirmButton } from '../../_ConfirmButton';
import { Pagination } from '../../_Pagination';
import { TaxonomyTabs } from '../_TaxonomyTabs';

/**
 * /admin/taxonomy/tags — mirrors the ingredients editor with the tag
 * field set (family fixed after create, name/description editable).
 */

const FAMILIES = ['diet', 'allergen', 'cuisine', 'prep', 'flavor'] as const;
const PAGE_SIZE = 100;
const EMPTY_FORM = { slug: '', name: '', path: '', family: 'diet', description: '' };

export default function AdminTagsPage() {
  const [family, setFamily] = useState('');
  const [offset, setOffset] = useState(0);
  const [refreshKey, setRefreshKey] = useState(0);
  const [data, setData] = useState<AdminTagsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchAdminTags({ family: family || undefined, limit: PAGE_SIZE, offset })
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [family, offset, refreshKey]);

  const onCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    try {
      await createTag({
        slug: form.slug.trim(),
        name: form.name.trim(),
        path: form.path.trim(),
        family: form.family,
        description: form.description.trim() || undefined,
      });
      setForm(EMPTY_FORM);
      setRefreshKey((k) => k + 1);
    } catch (err) {
      setCreateError(friendlyAdminError(err));
    } finally {
      setCreating(false);
    }
  };

  const onUpdated = (updated: AdminTag) => {
    setData((prev) =>
      prev ? { ...prev, tags: prev.tags.map((t) => (t.id === updated.id ? updated : t)) } : prev,
    );
  };

  return (
    <main data-testid="admin-tags">
      <div className="flex flex-wrap items-center justify-between gap-bw-3">
        <h1 className="text-bw-2xl font-bold text-zinc-900">Taxonomy</h1>
        <TaxonomyTabs />
      </div>

      <form
        onSubmit={(e) => void onCreate(e)}
        data-testid="tag-create-form"
        className="mt-bw-4 grid gap-bw-2 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-3 text-bw-sm sm:grid-cols-5"
      >
        <input
          value={form.slug}
          onChange={(e) => setForm({ ...form, slug: e.target.value })}
          placeholder="slug (diet-keto)"
          required
          data-testid="tag-new-slug"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <input
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="Name"
          required
          data-testid="tag-new-name"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <input
          value={form.path}
          onChange={(e) => setForm({ ...form, path: e.target.value })}
          placeholder="path (diet_keto)"
          required
          data-testid="tag-new-path"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        />
        <select
          value={form.family}
          onChange={(e) => setForm({ ...form, family: e.target.value })}
          data-testid="tag-new-family"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        >
          {FAMILIES.map((f) => (
            <option key={f} value={f}>
              {f}
            </option>
          ))}
        </select>
        <button
          type="submit"
          disabled={creating}
          data-testid="tag-create"
          className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
        >
          {creating ? 'Adding…' : 'Add'}
        </button>
        {createError && (
          <p role="alert" data-testid="tag-create-error" className="text-red-700 sm:col-span-5">
            {createError}
          </p>
        )}
      </form>

      <label className="mt-bw-4 flex items-center gap-bw-2 text-bw-sm text-zinc-700">
        Family
        <select
          value={family}
          onChange={(e) => {
            setFamily(e.target.value);
            setOffset(0);
          }}
          data-testid="tag-family-filter"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
        >
          <option value="">all</option>
          {FAMILIES.map((f) => (
            <option key={f} value={f}>
              {f}
            </option>
          ))}
        </select>
      </label>

      {error && (
        <div role="alert" data-testid="tags-error" className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900">
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
            {data.tags.map((tag) => (
              <TagRow
                key={tag.id}
                tag={tag}
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

function TagRow({
  tag,
  onUpdated,
  onDeleted,
}: {
  tag: AdminTag;
  onUpdated: (updated: AdminTag) => void;
  onDeleted: (id: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(tag.name);
  const [description, setDescription] = useState(tag.description ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      onUpdated(await updateTag(tag.id, { name, description }));
      setEditing(false);
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  const destroy = async () => {
    setBusy(true);
    setError(null);
    try {
      await deleteTag(tag.id);
      onDeleted(tag.id);
    } catch (e) {
      const refs = deleteRefusalCounts(e);
      if (refs) {
        const held = Object.entries(refs)
          .filter(([, n]) => n > 0)
          .map(([k, n]) => `${n} ${k}`)
          .join(', ');
        setError(`Still referenced — ${held}. Remove those references first.`);
      } else {
        setError(friendlyAdminError(e));
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <li data-testid={`tag-${tag.slug}`} className="rounded-bw-lg border border-zinc-200 bg-white p-bw-3">
      <div className="flex flex-wrap items-center justify-between gap-bw-2">
        <div className="min-w-0">
          <p className="font-semibold text-zinc-900">
            {tag.name}
            <span className="ml-bw-2 text-bw-xs font-normal uppercase tracking-wide text-zinc-400">
              {tag.family}
            </span>
          </p>
          <p className="mt-bw-1 text-bw-xs text-zinc-500">
            {tag.path.split('.').join(' › ')} · {tag.slug} · {tag.items_count} item
            {tag.items_count === 1 ? '' : 's'}
            {tag.description && <> · {tag.description}</>}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-bw-2 text-bw-sm">
          <button
            type="button"
            onClick={() => setEditing((v) => !v)}
            data-testid={`tag-edit-${tag.slug}`}
            className="font-semibold text-zinc-600 hover:text-bite"
          >
            {editing ? 'Close' : 'Edit'}
          </button>
          <ConfirmButton
            label="Delete"
            busy={busy}
            onConfirm={() => void destroy()}
            testId={`tag-delete-${tag.slug}`}
          />
        </div>
      </div>

      {editing && (
        <div className="mt-bw-3 grid gap-bw-2 border-t border-zinc-100 pt-bw-3 text-bw-sm sm:grid-cols-2">
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              data-testid={`tag-name-${tag.slug}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Description
            <input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              data-testid={`tag-description-${tag.slug}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <div className="flex items-center justify-end sm:col-span-2">
            <button
              type="button"
              onClick={() => void save()}
              disabled={busy}
              data-testid={`tag-save-${tag.slug}`}
              className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
            >
              {busy ? 'Saving…' : 'Save'}
            </button>
          </div>
        </div>
      )}

      {error && (
        <p role="alert" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </li>
  );
}
