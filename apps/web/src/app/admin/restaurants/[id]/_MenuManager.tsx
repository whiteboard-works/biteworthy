'use client';

import { useEffect, useState } from 'react';
import {
  createMenu,
  createSection,
  deleteMenu,
  deleteSection,
  fetchAdminMenus,
  structureErrorCopy,
  updateMenu,
  updateSection,
  type AdminMenu,
  type AdminMenuSection,
} from '../../../../lib/admin/structure';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { ConfirmButton } from '../../_ConfirmButton';

/**
 * `id` is optional in the generated schema, and a section without one
 * can't be addressed — PATCHing `/menu_sections/undefined` would 404.
 * Narrowing here is what lets the handlers below drop their `!`.
 */
function sectionsOf(menu: AdminMenu): Array<AdminMenuSection & { id: string }> {
  return (menu.sections ?? []).filter(
    (section): section is AdminMenuSection & { id: string } => typeof section.id === 'string',
  );
}

/**
 * Menus → sections for one restaurant. A scan usually lands every dish
 * in one bucket, so this is where an admin splits it into "Lunch /
 * Tacos", "Dinner / Mains" and so on.
 *
 * Deleting is safe by construction: a section's dishes are unsectioned,
 * never deleted (the API returns how many), and deleting a menu takes
 * its sections but leaves every item standing. The confirm copy says
 * so rather than implying a destructive cascade.
 */
export function MenuManager({
  restaurantId,
  onTreeChanged,
}: {
  restaurantId: string;
  /** Lets the parent refresh the item rows' section select. */
  onTreeChanged?: (menus: AdminMenu[]) => void;
}) {
  const [menus, setMenus] = useState<AdminMenu[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [newMenu, setNewMenu] = useState('');
  const [newSection, setNewSection] = useState<Record<string, string>>({});

  const load = async () => {
    const res = await fetchAdminMenus(restaurantId);
    setMenus(res.menus);
    onTreeChanged?.(res.menus);
  };

  useEffect(() => {
    let active = true;
    fetchAdminMenus(restaurantId)
      .then((res) => {
        if (!active) return;
        setMenus(res.menus);
        onTreeChanged?.(res.menus);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
    // onTreeChanged is re-created per parent render; depending on it
    // would refetch the tree on every keystroke elsewhere on the page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [restaurantId]);

  const run = async (action: () => Promise<unknown>, message?: string) => {
    // Rename-on-blur isn't behind a disabled button, so it can fire
    // while a create or delete is still in flight. Two overlapping runs
    // race on the tree and the first to finish re-enables everything.
    if (busy) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      await action();
      await load();
      if (message) setNotice(message);
    } catch (e) {
      // A refresh that fails after the write succeeded would otherwise
      // leave a success notice sitting next to the error.
      setNotice(null);
      setError(structureErrorCopy(e) ?? friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  /**
   * A rename fires on blur, which in a browser lands BEFORE the click
   * that caused it. Running immediately would flip `busy` and disable
   * the delete button the admin was in the middle of pressing, so the
   * click never dispatches and they have to press it twice. Yielding a
   * task lets the click through first.
   */
  const runDeferred = (action: () => Promise<unknown>) => {
    setTimeout(() => void run(action), 0);
  };

  return (
    <section
      data-testid="menu-manager"
      aria-labelledby="menus-heading"
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
    >
      <h2 id="menus-heading" className="text-bw-sm font-semibold text-zinc-600">
        Menus &amp; sections
      </h2>

      {error && (
        <p role="alert" data-testid="menus-error" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
      {notice && (
        <p role="status" data-testid="menus-notice" className="mt-bw-2 text-bw-sm text-ok">
          {notice}
        </p>
      )}

      {!menus && !error && (
        <p role="status" className="mt-bw-2 text-bw-sm text-zinc-500">
          Loading menus…
        </p>
      )}

      {menus && (
        <ul className="mt-bw-3 space-y-bw-3">
          {menus.map((menu) => (
            <li
              key={menu.id}
              data-testid={`menu-${menu.id}`}
              className="rounded-bw-md border border-zinc-100 p-bw-3"
            >
              <div className="flex flex-wrap items-center justify-between gap-bw-2">
                <input
                  defaultValue={menu.name}
                  onBlur={(e) => {
                    if (e.target.value.trim() && e.target.value !== menu.name) {
                      runDeferred(() => updateMenu(menu.id, { name: e.target.value.trim() }));
                    }
                  }}
                  aria-label={`Menu name for ${menu.name}`}
                  data-testid={`menu-name-${menu.id}`}
                  className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-sm font-semibold"
                />
                <ConfirmButton
                  label="Delete menu"
                  confirmLabel="Confirm — delete menu (dishes stay)"
                  busy={busy}
                  onConfirm={() =>
                    void run(
                      () => deleteMenu(menu.id),
                      'Menu deleted — its dishes are unsectioned.',
                    )
                  }
                  testId={`menu-delete-${menu.id}`}
                />
              </div>

              <ul className="mt-bw-2 space-y-bw-1 pl-bw-3">
                {sectionsOf(menu).map((section) => (
                  <li
                    key={section.id}
                    data-testid={`section-${section.id}`}
                    className="flex flex-wrap items-center justify-between gap-bw-2 text-bw-sm"
                  >
                    <span className="flex items-center gap-bw-2">
                      <input
                        defaultValue={section.name}
                        onBlur={(e) => {
                          if (e.target.value.trim() && e.target.value !== section.name) {
                            runDeferred(() =>
                              updateSection(section.id, { name: e.target.value.trim() }),
                            );
                          }
                        }}
                        aria-label={`Section name for ${section.name}`}
                        data-testid={`section-name-${section.id}`}
                        className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
                      />
                      <span className="text-bw-xs text-zinc-500">
                        {section.items_count ?? 0} dish
                        {(section.items_count ?? 0) === 1 ? '' : 'es'}
                      </span>
                    </span>
                    <ConfirmButton
                      label="Delete section"
                      confirmLabel="Confirm — delete section (dishes stay)"
                      busy={busy}
                      onConfirm={() =>
                        void run(async () => {
                          const unsectioned = await deleteSection(section.id);
                          setNotice(
                            `Section deleted — ${unsectioned} dish${unsectioned === 1 ? '' : 'es'} kept, now unsectioned.`,
                          );
                        })
                      }
                      testId={`section-delete-${section.id}`}
                    />
                  </li>
                ))}
                {sectionsOf(menu).length === 0 && (
                  <li className="text-bw-xs italic text-zinc-400">no sections yet</li>
                )}
              </ul>

              <div className="mt-bw-2 flex items-center gap-bw-2 pl-bw-3">
                <input
                  value={newSection[menu.id] ?? ''}
                  onChange={(e) =>
                    setNewSection((prev) => ({ ...prev, [menu.id]: e.target.value }))
                  }
                  placeholder="New section name"
                  aria-label={`New section for ${menu.name}`}
                  data-testid={`section-new-${menu.id}`}
                  className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
                />
                <button
                  type="button"
                  disabled={busy || !(newSection[menu.id] ?? '').trim()}
                  onClick={() =>
                    void run(async () => {
                      await createSection(menu.id, { name: (newSection[menu.id] ?? '').trim() });
                      setNewSection((prev) => ({ ...prev, [menu.id]: '' }));
                    })
                  }
                  data-testid={`section-add-${menu.id}`}
                  className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs font-semibold text-zinc-700 disabled:opacity-50"
                >
                  Add section
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <div className="mt-bw-3 flex items-center gap-bw-2">
        <input
          value={newMenu}
          onChange={(e) => setNewMenu(e.target.value)}
          placeholder="New menu name (e.g. Dinner)"
          aria-label="New menu name"
          data-testid="menu-new"
          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-sm"
        />
        <button
          type="button"
          disabled={busy || !newMenu.trim()}
          onClick={() =>
            void run(async () => {
              await createMenu(restaurantId, { name: newMenu.trim() });
              setNewMenu('');
            })
          }
          data-testid="menu-add"
          className="rounded-bw-md bg-bite px-bw-3 py-bw-1 text-bw-sm font-semibold text-white disabled:opacity-50"
        >
          Add menu
        </button>
      </div>
    </section>
  );
}
