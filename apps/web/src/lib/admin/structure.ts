/**
 * Menus, sections, address and hours — the restaurant scaffolding an
 * admin reorganizes after a scan dumps everything into one bucket.
 *
 * Hours are a WHOLE-WEEK replace, matching the server: a per-day write
 * could land half-applied and advertise the wrong opening time. Blank
 * times mean closed.
 */
import type { paths } from '@biteworthy/api-types';
import {
  AdminError,
  deleteAdmin,
  getAdminJson,
  patchAdminJson,
  postAdminJson,
  toAdminError,
} from './shared';

export type AdminMenusResponse =
  paths['/api/v1/admin/restaurants/{restaurant_id}/menus']['get']['responses']['200']['content']['application/json'];
export type AdminMenu = AdminMenusResponse['menus'][number];
export type AdminMenuSection = NonNullable<AdminMenu['sections']>[number];

export type AdminPlace =
  paths['/api/v1/admin/restaurants/{id}/place']['get']['responses']['200']['content']['application/json'];

export interface HourRow {
  day_of_week: number;
  opens_at: string | null;
  closes_at: string | null;
}

export const DAY_NAMES = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
] as const;

export function fetchAdminMenus(
  restaurantId: string,
  fetchImpl?: typeof fetch,
): Promise<AdminMenusResponse> {
  return getAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/menus`,
    fetchImpl,
  );
}

export function createMenu(
  restaurantId: string,
  body: { name: string; position?: number },
  fetchImpl?: typeof fetch,
): Promise<AdminMenu> {
  return postAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/menus`,
    { body },
    fetchImpl,
  );
}

export function updateMenu(
  menuId: string,
  body: { name?: string; description?: string | null; position?: number },
  fetchImpl?: typeof fetch,
): Promise<AdminMenu> {
  return patchAdminJson(`/api/admin/menus/${encodeURIComponent(menuId)}`, body, fetchImpl);
}

export function deleteMenu(menuId: string, fetchImpl?: typeof fetch): Promise<void> {
  return deleteAdmin(`/api/admin/menus/${encodeURIComponent(menuId)}`, fetchImpl);
}

export function createSection(
  menuId: string,
  body: { name: string; position?: number },
  fetchImpl?: typeof fetch,
): Promise<AdminMenuSection> {
  return postAdminJson(
    `/api/admin/menus/${encodeURIComponent(menuId)}/menu_sections`,
    { body },
    fetchImpl,
  );
}

export function updateSection(
  sectionId: string,
  body: { name?: string; position?: number },
  fetchImpl?: typeof fetch,
): Promise<AdminMenuSection> {
  return patchAdminJson(
    `/api/admin/menu_sections/${encodeURIComponent(sectionId)}`,
    body,
    fetchImpl,
  );
}

/**
 * Resolves with the count of items left unsectioned — deleting a
 * section never deletes its dishes, and the count is what the UI
 * reports back so that's visible.
 */
export async function deleteSection(
  sectionId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<number> {
  const res = await fetchImpl(`/api/admin/menu_sections/${encodeURIComponent(sectionId)}`, {
    method: 'DELETE',
    credentials: 'same-origin',
  });
  if (!res.ok) throw await toAdminError(res);
  const body = (await res.json()) as { items_unsectioned?: number };
  return body.items_unsectioned ?? 0;
}

export function fetchAdminPlace(
  restaurantId: string,
  fetchImpl?: typeof fetch,
): Promise<AdminPlace> {
  return getAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/place`,
    fetchImpl,
  );
}

export function saveAddress(
  restaurantId: string,
  body: Record<string, string | number | null>,
  fetchImpl: typeof fetch = fetch,
): Promise<AdminPlace> {
  return putAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/address`,
    body,
    fetchImpl,
  );
}

export function saveHours(
  restaurantId: string,
  hours: HourRow[],
  fetchImpl: typeof fetch = fetch,
): Promise<AdminPlace> {
  return putAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/hours`,
    { hours },
    fetchImpl,
  );
}

/** PUT is only used by the two wholesale-replace endpoints. */
async function putAdminJson<T>(path: string, body: unknown, fetchImpl: typeof fetch): Promise<T> {
  const res = await fetchImpl(path, {
    method: 'PUT',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw await toAdminError(res);
  return (await res.json()) as T;
}

/** Human copy for the structure endpoints' structured refusals. */
export function structureErrorCopy(err: unknown): string | null {
  if (!(err instanceof AdminError)) return null;
  const body = err.body as { error?: string; values?: unknown[]; field?: string } | undefined;
  switch (body?.error) {
    case 'invalid_day_of_week':
      return `Not a day of the week: ${(body.values ?? []).join(', ')}.`;
    case 'invalid_time_of_day':
      return `Times must look like 17:30 — got ${(body.values ?? []).join(', ')}.`;
    case 'closed_day_has_hours': {
      const days = (body.values ?? []).map((v) => DAY_NAMES[Number(v)] ?? v).join(', ');
      return `${days || 'A day'} is set both closed and open — clear one or the other.`;
    }
    case 'hour_rows_must_be_objects':
    case 'hours_must_be_an_array':
      return 'Those hours could not be read.';
    case 'invalid_coordinate':
      return `${body.field ?? 'Coordinate'} must be a number.`;
    case 'invalid_name':
      return 'Give it a name.';
    case 'invalid_position':
      return 'Position must be a whole number.';
    default:
      return null;
  }
}
