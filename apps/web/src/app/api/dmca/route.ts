/**
 * Legal remediation E10 — Next proxy for the DMCA takedown form.
 *
 * `POST /api/dmca` from the /dmca page forwards to the Rails
 * `POST /api/v1/dmca_notices`. Keeps the API base server-side so the
 * browser makes a same-origin request (no CORS preflight).
 */
import { NextResponse, type NextRequest } from 'next/server';

import { API_BASE } from '../../../lib/api-base';

interface DmcaBody {
  complainant_name?: string;
  complainant_email?: string;
  infringing_url?: string;
  work_description?: string;
  good_faith?: boolean;
  accuracy_sworn?: boolean;
  signature?: string;
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const body = (await request.json().catch(() => ({}))) as DmcaBody;

  const upstream = await fetch(`${API_BASE}/api/v1/dmca_notices`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ dmca_notice: body }),
  });

  const responseBody = await upstream.json().catch(() => ({}));
  return NextResponse.json(responseBody, { status: upstream.status });
}
