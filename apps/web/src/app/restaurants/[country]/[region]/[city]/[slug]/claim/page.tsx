'use client';

import { useParams, useSearchParams } from 'next/navigation';
import { ClaimVerify } from './_ClaimVerify';

/** The mailer's link points here: `<web_path>/claim?t=<token>`. */
export default function ClaimVerifyPage() {
  const params = useParams<{ slug: string }>();
  const search = useSearchParams();
  return <ClaimVerify slug={params.slug} token={search.get('t') ?? ''} />;
}
