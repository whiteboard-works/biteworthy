'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

/** Ingredients | Tags switcher shared by the two taxonomy pages. */
export function TaxonomyTabs() {
  const pathname = usePathname();

  const link = (href: '/admin/taxonomy/ingredients' | '/admin/taxonomy/tags', label: string) => (
    <Link
      href={href}
      aria-current={pathname === href ? 'page' : undefined}
      className={
        pathname === href
          ? 'rounded-bw-pill bg-bite px-bw-3 py-bw-1 font-semibold text-white'
          : 'rounded-bw-pill border border-zinc-300 px-bw-3 py-bw-1 font-semibold text-zinc-600 hover:border-bite hover:text-bite'
      }
    >
      {label}
    </Link>
  );

  return (
    <div data-testid="taxonomy-tabs" className="flex items-center gap-bw-2 text-bw-sm">
      {link('/admin/taxonomy/ingredients', 'Ingredients')}
      {link('/admin/taxonomy/tags', 'Tags')}
    </div>
  );
}
