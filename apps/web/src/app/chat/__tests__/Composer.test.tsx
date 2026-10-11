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

  const clipboard = (files: File[], text = '') => ({
    clipboardData: {
      files,
      types: text ? ['text/plain', 'Files'] : ['Files'],
      getData: () => text,
    },
  });

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

  it('leaves an unlabeled file for the API to sniff (a dragged HEIC arrives with no type)', async () => {
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

    fireEvent.dragLeave(zone, { dataTransfer: { types: ['Files'] } });
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

    fireEvent.paste(box, clipboard([photo('image.png', 'image/png')]));

    await waitFor(() => expect(chips()).toContain('image.png'));
  });

  it('leaves a text paste alone even when the clipboard also carries an image', () => {
    // Copying cells from a spreadsheet puts both the text and a picture of
    // it on the clipboard; the user meant the text.
    const { box } = setup();

    fireEvent.paste(box, clipboard([photo('cells.png', 'image/png')], 'Burger\t12.00'));

    expect(upload).not.toHaveBeenCalled();
  });

  it('attaches a file copied in Finder, which also puts its name on the clipboard', async () => {
    const { box } = setup();

    fireEvent.paste(box, clipboard([photo('menu.jpg')], 'menu.jpg'));

    await waitFor(() => expect(chips()).toContain('menu.jpg'));
  });

  it('keeps Send off until every upload in flight has landed', async () => {
    // A paste during a slow drop must not let Send go out without the drop's pages.
    let finishDrop: () => void = () => {};
    upload.mockImplementationOnce(
      (file: File) =>
        new Promise((resolve) => {
          finishDrop = () =>
            resolve({ id: 'slow', filename: file.name, content_type: file.type, byte_size: 1 });
        }),
    );
    const { zone, box } = setup();
    const sendButton = screen.getByRole('button', { name: 'Send' }) as HTMLButtonElement;

    fireEvent.drop(zone, { dataTransfer: { files: [photo('page1.jpg')], types: ['Files'] } });
    fireEvent.paste(box, clipboard([photo('shot.png', 'image/png')]));
    await waitFor(() => expect(chips()).toContain('shot.png'));
    expect(sendButton.disabled).toBe(true);

    finishDrop();
    await waitFor(() => expect(sendButton.disabled).toBe(false));
    expect(chips()).toContain('page1.jpg');
  });

  it('keeps the pages that uploaded when one in the same drop fails', async () => {
    upload.mockImplementation(async (file: File) => {
      if (file.name === 'huge.jpg')
        throw new Error('That file is too large to upload (20 MB max).');
      return { id: file.name, filename: file.name, content_type: file.type, byte_size: 1 };
    });
    const { zone } = setup();

    fireEvent.drop(zone, {
      dataTransfer: {
        files: [
          photo('notes.txt', 'text/plain'),
          photo('p1.jpg'),
          photo('huge.jpg'),
          photo('p3.jpg'),
        ],
        types: ['Files'],
      },
    });

    await waitFor(() => expect(chips()).toContain('p3.jpg'));
    expect(chips()).toContain('p1.jpg');
    const alert = screen.getByRole('alert').textContent ?? '';
    expect(alert).toContain('notes.txt');
    expect(alert).toContain('huge.jpg');
  });

  it("keeps the drop target up while the drag crosses the composer's own controls", () => {
    const { zone, box } = setup();

    fireEvent.dragEnter(zone, { dataTransfer: { types: ['Files'] } });
    fireEvent.dragEnter(box, { dataTransfer: { types: ['Files'] } });
    fireEvent.dragLeave(zone, { dataTransfer: { types: ['Files'] }, relatedTarget: null });
    expect(screen.getByText('Drop menu photos here')).toBeTruthy();

    fireEvent.dragLeave(box, { dataTransfer: { types: ['Files'] }, relatedTarget: null });
    expect(screen.queryByText('Drop menu photos here')).toBeNull();
  });
});
