import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

import { uploadAttachment } from '../../../lib/chat';
import { Composer } from '../_Composer';

vi.mock('../../../lib/chat', async () => {
  const actual = await vi.importActual<typeof import('../../../lib/chat')>('../../../lib/chat');
  return { ...actual, uploadAttachment: vi.fn() };
});

/**
 * The message box grows with what is typed. It used to sit at one row
 * with a drag handle as the only way taller — and iOS Safari draws no
 * handle, so on a phone a long message scrolled inside a one-line slot.
 */
describe('Composer message box', () => {
  const LINE = 24;
  // Top + bottom border: scrollHeight leaves it out, a border-box height counts it.
  const BORDER = 2;
  const stubbed = ['scrollHeight', 'offsetHeight', 'clientHeight'] as const;

  // jsdom does no layout; stand in one line of height per line of text.
  beforeEach(() => {
    const lines = (el: HTMLTextAreaElement) => el.value.split('\n').length * LINE;
    const getters = {
      scrollHeight: lines,
      clientHeight: lines,
      offsetHeight: (el: HTMLTextAreaElement) => lines(el) + BORDER,
    };
    for (const name of stubbed) {
      Object.defineProperty(HTMLTextAreaElement.prototype, name, {
        configurable: true,
        get(this: HTMLTextAreaElement) {
          return getters[name](this);
        },
      });
    }
  });

  afterEach(() => {
    for (const name of stubbed) {
      Reflect.deleteProperty(HTMLTextAreaElement.prototype, name);
    }
  });

  function setup() {
    const onSend = vi.fn();
    render(<Composer queueing={false} queued={[]} onSend={onSend} onCancelQueued={() => {}} />);
    return { box: screen.getByRole('textbox', { name: 'Message' }), onSend };
  }

  it('grows to fit a multi-line message', () => {
    const { box } = setup();

    fireEvent.change(box, { target: { value: 'run the retag\ndry runs\nagainst prod' } });

    expect(box.style.height).toBe(`${3 * LINE + BORDER}px`);
  });

  it('shrinks back to one line once the message is sent', () => {
    const { box, onSend } = setup();
    fireEvent.change(box, { target: { value: 'one\ntwo\nthree' } });

    fireEvent.keyDown(box, { key: 'Enter' });

    expect(onSend).toHaveBeenCalledWith('one\ntwo\nthree', []);
    expect(box.style.height).toBe(`${LINE + BORDER}px`);
  });
});

/**
 * A menu photo is usually already on screen — in Finder, a camera roll
 * synced to the laptop, or a screenshot just taken. Dragging it onto the
 * composer or pasting it into the box attaches it the same way the + picker
 * does: it becomes a chip, and nothing sends until Send.
 */
describe('Composer drop and paste', () => {
  const upload = vi.mocked(uploadAttachment);

  beforeEach(() => {
    upload.mockReset();
    upload.mockImplementation(async (file: File) => ({
      id: `id-${file.name}`,
      filename: file.name,
      content_type: file.type,
      byte_size: file.size,
    }));
  });

  const photo = (name = 'menu.jpg', type = 'image/jpeg') => new File(['x'], name, { type });

  function setup() {
    const onSend = vi.fn();
    render(<Composer queueing={false} queued={[]} onSend={onSend} onCancelQueued={() => {}} />);
    return {
      zone: screen.getByTestId('composer'),
      box: screen.getByRole('textbox', { name: 'Message' }),
      onSend,
    };
  }

  const chips = () => screen.queryByTestId('attachment-chips')?.textContent ?? '';

  it('attaches dropped photos as chips without sending them', async () => {
    const { zone, onSend } = setup();

    fireEvent.drop(zone, {
      dataTransfer: {
        files: [photo('front.jpg'), photo('back.png', 'image/png')],
        types: ['Files'],
      },
    });

    await waitFor(() => expect(chips()).toContain('back.png'));
    expect(chips()).toContain('front.jpg');
    expect(onSend).not.toHaveBeenCalled();
  });

  it('skips files the scanner cannot read, says so, and keeps the rest', async () => {
    const { zone } = setup();

    fireEvent.drop(zone, {
      dataTransfer: {
        files: [photo('notes.txt', 'text/plain'), photo('menu.pdf', 'application/pdf')],
        types: ['Files'],
      },
    });

    await waitFor(() => expect(chips()).toContain('menu.pdf'));
    expect(chips()).not.toContain('notes.txt');
    expect(upload).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('alert').textContent).toContain('notes.txt');
  });

  it('accepts a HEIC photo the browser could not label', async () => {
    const { zone } = setup();

    fireEvent.drop(zone, {
      dataTransfer: { files: [photo('IMG_0001.HEIC', '')], types: ['Files'] },
    });

    await waitFor(() => expect(chips()).toContain('IMG_0001.HEIC'));
  });

  it('shows the drop target only while files are dragged over it', () => {
    const { zone } = setup();

    fireEvent.dragEnter(zone, { dataTransfer: { types: ['text/plain'] } });
    expect(screen.queryByText('Drop menu photos here')).toBeNull();

    fireEvent.dragEnter(zone, { dataTransfer: { types: ['Files'] } });
    expect(screen.getByText('Drop menu photos here')).toBeTruthy();

    fireEvent.dragLeave(zone, { relatedTarget: null });
    expect(screen.queryByText('Drop menu photos here')).toBeNull();
  });

  it('lets dragged text land in the message box', () => {
    const { box } = setup();

    const notCanceled = fireEvent.drop(box, { dataTransfer: { files: [], types: ['text/plain'] } });

    expect(notCanceled).toBe(true);
    expect(upload).not.toHaveBeenCalled();
  });

  it('attaches a pasted screenshot', async () => {
    const { box } = setup();

    fireEvent.paste(box, {
      clipboardData: { files: [photo('image.png', 'image/png')], types: ['Files'] },
    });

    await waitFor(() => expect(chips()).toContain('image.png'));
  });

  it('leaves a text paste alone even when the clipboard also carries an image', () => {
    // Copying cells from a spreadsheet puts both the text and a picture of
    // it on the clipboard; the user meant the text.
    const { box } = setup();

    fireEvent.paste(box, {
      clipboardData: { files: [photo('cells.png', 'image/png')], types: ['text/plain', 'Files'] },
    });

    expect(upload).not.toHaveBeenCalled();
  });
});
