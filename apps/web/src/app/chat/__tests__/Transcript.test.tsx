import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';

import type { ChatMessage } from '../../../lib/chat';
import { Transcript } from '../_Transcript';

/**
 * The user bubble. Its text carries a manifest line per upload because
 * the model needs the signed id to start a scan — but that line is
 * machinery, and it was reaching people as a wall of base64.
 */
describe('Transcript user bubble', () => {
  function sent(text: string): ChatMessage {
    return { id: 'm-1', role: 'user', position: 1, blocks: [{ type: 'text', text }] };
  }

  function show(text: string, previews: Record<string, string> = {}) {
    render(
      <Transcript
        messages={[sent(text)]}
        live={null}
        pending={null}
        busy={false}
        onAnswer={() => {}}
        previews={(id) => previews[id]}
      />,
    );
    return screen.getByTestId('user-message');
  }

  const manifest = '[Attached IMG_7978.jpg — attachment_id: eyJfcmFpbHMi--c2eb6325]';

  it('never shows the attachment id', () => {
    const bubble = show(`Can you add these?\n\n${manifest}`);

    expect(bubble).toHaveTextContent('Can you add these?');
    expect(bubble).not.toHaveTextContent('attachment_id');
    expect(bubble).not.toHaveTextContent('eyJfcmFpbHMi');
  });

  // Same session as the upload: the photo is still on the device.
  it('shows the photo when this session still has it', () => {
    const bubble = show(`Can you add these?\n\n${manifest}`, {
      'eyJfcmFpbHMi--c2eb6325': 'blob:preview-1',
    });

    expect(within(bubble).getByRole('img', { name: 'IMG_7978.jpg' })).toHaveAttribute(
      'src',
      'blob:preview-1',
    );
  });

  // Reloaded, opened from History, or on another device: nothing local to
  // show, but the person should still see that a file went with it.
  it('falls back to the filename when there is no local photo', () => {
    const bubble = show(manifest);

    expect(within(bubble).queryByRole('img')).toBeNull();
    expect(within(bubble).getByTestId('attachment-file')).toHaveTextContent('IMG_7978.jpg');
  });

  it('leaves a plain message as it was typed', () => {
    expect(show('what can I eat')).toHaveTextContent('what can I eat');
  });
});
