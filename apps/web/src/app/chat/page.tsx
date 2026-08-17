import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { redirect } from 'next/navigation';
import { getServerJwt } from '../../lib/server-auth';
import { ChatClient } from './_ChatClient';

export const metadata: Metadata = {
  title: 'Chat — BiteWorthy',
  description: 'Ask what you can eat, or add a menu by photo, PDF, link, or text.',
  // A private conversation has nothing to index.
  robots: { index: false, follow: false },
};

export default async function ChatPage(): Promise<ReactElement> {
  // Bounce anonymous visitors server-side, before the empty chat shell
  // can flash. Presence-only check — an expired or invalid JWT still
  // renders and falls through to ChatClient's own 401 handling.
  const jwt = await getServerJwt();
  if (!jwt) redirect('/login?next=%2Fchat');
  return <ChatClient />;
}
