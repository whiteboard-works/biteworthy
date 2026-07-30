'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

/**
 * Tab bar for the /admin section. Tabs are added PR-by-PR as their
 * routes ship — typedRoutes fails the build on links to routes that
 * don't exist yet.
 */
const TABS = [{ href: '/admin', label: 'Dashboard' }] as const;

export function AdminNav() {
  const pathname = usePathname();

  return (
    <nav
      data-testid="admin-nav"
      className="mb-bw-6 flex items-center gap-bw-4 border-b border-zinc-200 pb-bw-3 text-bw-sm"
    >
      <span className="font-bold text-zinc-900">Admin</span>
      {TABS.map((tab) => {
        const active =
          tab.href === '/admin' ? pathname === '/admin' : pathname.startsWith(tab.href);
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
