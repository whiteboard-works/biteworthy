import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

import { Composer } from '../_Composer';

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
