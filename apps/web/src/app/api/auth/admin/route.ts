/**
 * `GET /api/auth/admin` → `{ admin }` — whether the signed-in user is
 * an admin, resolved via Rails `GET /api/v1/me`. Backs the header's
 * Admin link only; the /admin layout re-checks server-side and Rails
 * gates every admin API call. Fails safe to `false` — the opposite
 * direction from /api/auth/onboarded, deliberately: hiding the link
 * from a real admin is harmless (they can type /admin), showing it to
 * a non-admin is noise.
 */
import { NextResponse } from 'next/server';
import { getServerJwt } from '../../../../lib/server-auth';
import { jwtIsAdmin } from '../../../../lib/admin-auth';

export async function GET() {
  return NextResponse.json(
    { admin: await jwtIsAdmin(await getServerJwt()) },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
