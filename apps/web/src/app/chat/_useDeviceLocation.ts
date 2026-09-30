'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type { DeviceLocation } from '../../lib/chat';

const KEY = 'bw_chat_use_location';
// A fix this old is still the right neighbourhood; refreshed in the
// background rather than holding a send for a new one.
const MAX_AGE_MS = 5 * 60 * 1000;
// How long a send holds for a first fix that is on its way. Long enough
// for a warm GPS or wifi fix; short enough that a slow one costs the sort,
// not the message.
const FIRST_FIX_WAIT_MS = 3_000;

export type LocationStatus = 'off' | 'locating' | 'on' | 'denied' | 'unavailable';

export interface DeviceLocationControl {
  status: LocationStatus;
  toggle: () => void;
  /** The latest fix, read at send time rather than render time, so a
   *  message that sat in the queue goes out with where they are now.
   *  Waits briefly when the control is on and the first fix is still
   *  coming, so a message sent right after a reload is not quietly sent
   *  without the location the lit pin promises. */
  current: () => Promise<DeviceLocation | undefined>;
}

/**
 * "Use my location" for the chat. Off until the person turns it on; the
 * choice is remembered per browser, the position never is. It rides with
 * each message while on and the API forgets it once that turn is done.
 *
 * Coarsened here as well as on the server (three decimals, ~110 m): what
 * never leaves the browser cannot be logged anywhere on the way.
 */
export function useDeviceLocation(): DeviceLocationControl {
  const [status, setStatus] = useState<LocationStatus>('off');
  const enabled = useRef(false);
  const fix = useRef<{ location: DeviceLocation; at: number } | null>(null);
  const locating = useRef(false);
  // Sends waiting on the first fix; settled by whichever callback runs.
  const waiters = useRef<((location: DeviceLocation | undefined) => void)[]>([]);

  const settle = useCallback((location: DeviceLocation | undefined): void => {
    locating.current = false;
    const waiting = waiters.current;
    waiters.current = [];
    waiting.forEach((resolve) => resolve(location));
  }, []);

  const locate = useCallback(() => {
    if (!supported()) {
      enabled.current = false;
      remember(false);
      setStatus('unavailable');
      return;
    }
    if (locating.current) return;
    locating.current = true;
    if (!fix.current) setStatus('locating');
    navigator.geolocation.getCurrentPosition(
      (position) => {
        if (!enabled.current) return settle(undefined);
        fix.current = {
          location: {
            lat: coarse(position.coords.latitude),
            lng: coarse(position.coords.longitude),
            accuracy_m: Math.round(position.coords.accuracy),
          },
          // The fix's own age, not ours: `maximumAge` lets the browser
          // hand back a cached position, and stamping it "now" would let
          // it pass as fresh for another five minutes.
          at: position.timestamp || Date.now(),
        };
        setStatus('on');
        settle(fix.current.location);
      },
      (error) => {
        if (enabled.current && error.code === error.PERMISSION_DENIED) {
          enabled.current = false;
          fix.current = null;
          remember(false);
          setStatus('denied');
        } else if (enabled.current && !fix.current) {
          // Still on, so the next tap retries rather than turning it
          // off; a timeout on a refresh keeps the fix already in hand.
          setStatus('unavailable');
        }
        settle(undefined);
      },
      { enableHighAccuracy: false, maximumAge: MAX_AGE_MS, timeout: 15_000 },
    );
  }, [settle]);

  // Read in an effect: the server has no `localStorage`, and reading it
  // during render would hydrate a different tree than the server sent.
  useEffect(() => {
    let on = false;
    try {
      on = window.localStorage.getItem(KEY) === 'on';
    } catch {
      // Private mode, or storage disabled. Off stands.
    }
    if (on) {
      enabled.current = true;
      locate();
    }
  }, [locate]);

  const toggle = useCallback(() => {
    // On with nothing to show for it (a timeout) reads as off, so a tap
    // there means "try again", not "stop".
    if (enabled.current && !fix.current && !locating.current) {
      locate();
      return;
    }
    if (enabled.current) {
      enabled.current = false;
      fix.current = null;
      remember(false);
      setStatus('off');
      settle(undefined);
      return;
    }
    if (!supported()) {
      setStatus('unavailable');
      return;
    }
    enabled.current = true;
    remember(true);
    locate();
  }, [locate, settle]);

  const current = useCallback(async (): Promise<DeviceLocation | undefined> => {
    if (!enabled.current) return undefined;
    if (fix.current) {
      if (Date.now() - fix.current.at > MAX_AGE_MS) locate();
      return fix.current.location;
    }
    if (!locating.current) return undefined;
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        waiters.current = waiters.current.filter((waiter) => waiter !== done);
        resolve(undefined);
      }, FIRST_FIX_WAIT_MS);
      const done = (location: DeviceLocation | undefined): void => {
        clearTimeout(timer);
        resolve(location);
      };
      waiters.current.push(done);
    });
  }, [locate]);

  return { status, toggle, current };
}

function supported(): boolean {
  return typeof navigator !== 'undefined' && Boolean(navigator.geolocation);
}

function coarse(degrees: number): number {
  return Math.round(degrees * 1000) / 1000;
}

function remember(on: boolean): void {
  try {
    if (on) window.localStorage.setItem(KEY, 'on');
    else window.localStorage.removeItem(KEY);
  } catch {
    // Not being able to remember the choice is not a reason to refuse
    // it for this session.
  }
}
