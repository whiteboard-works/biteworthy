'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

/**
 * Tab bar for the /admin section. Tabs are added PR-by-PR as their
 * routes ship — typedRoutes fails the production (`next build`) build
 * on links to routes that don't exist yet. (CI's bare `tsc` doesn't
 * regenerate route types, so Vercel's build is where this actually
 * bites.)
 */
const TABS = [
  { href: '/admin', label: 'Dashboard' },
  { href: '/admin/runs', label: 'Runs' },
  { href: '/admin/reviews', label: 'Reviews' },
  { href: '/admin/suggestions', label: 'Suggestions' },
  // `match` widens the active state to sibling sub-pages (tags).
  { href: '/admin/taxonomy/ingredients', label: 'Taxonomy', match: '/admin/taxonomy' },
  { href: '/admin/restaurants', label: 'Restaurants' },
  { href: '/admin/users', label: 'Users' },
] as const;

export function AdminNav() {
  const pathname = usePathname();

  return (
    <nav
      data-testid="admin-nav"
      className="mb-bw-6 flex items-center gap-bw-4 border-b border-zinc-200 pb-bw-3 text-bw-sm"
    >
      <span className="font-bold text-zinc-900">Admin</span>
      {TABS.map((tab) => {
        const prefix = 'match' in tab ? tab.match : tab.href;
        const active = tab.href === '/admin' ? pathname === '/admin' : pathname.startsWith(prefix);
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={
              active ? 'font-semibold text-bite' : 'font-semibold text-zinc-600 hover:text-bite-dark'
            }
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
