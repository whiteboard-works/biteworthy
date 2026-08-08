import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { ChatClient } from './_ChatClient';

export const metadata: Metadata = {
  title: 'Chat — BiteWorthy',
  description: 'Ask what you can eat, or add a menu by photo, PDF, link, or text.',
  // A private conversation has nothing to index.
  robots: { index: false, follow: false },
};

export default function ChatPage(): ReactElement {
  return <ChatClient />;
}
