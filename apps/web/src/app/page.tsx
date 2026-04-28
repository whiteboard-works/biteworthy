import type { ReactElement } from 'react';

export default function HomePage(): ReactElement {
  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col justify-center gap-6 px-6">
      <span className="text-bite text-sm font-medium uppercase tracking-wider">BiteWorthy</span>
      <h1 className="text-4xl font-bold leading-tight md:text-5xl">
        Scan any menu, see only what you can eat.
      </h1>
      <p className="text-lg text-zinc-600">
        A pocket food filter for allergies, intolerances, and dietary needs. Built for
        independent restaurants — not just chains.
      </p>
      <p className="text-sm text-zinc-400">
        Pre-MVP. The mobile app and the contributor tools are wired up next.
      </p>
    </main>
  );
}
