'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type { DeviceLocation } from '../../lib/chat';

const KEY = 'bw_chat_use_location';
// A fix this old is still the right neighbourhood; refreshed in the
// background rather than holding a send for a new one.
const MAX_AGE_MS = 5 * 60 * 1000;

export type LocationStatus = 'off' | 'locating' | 'on' | 'denied' | 'unavailable';

export interface DeviceLocationControl {
  status: LocationStatus;
  toggle: () => void;
  /** The latest fix, read at send time rather than render time, so a
   *  message that sat in the queue goes out with where they are now. */
  current: () => DeviceLocation | undefined;
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

  const locate = useCallback(() => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      enabled.current = false;
      setStatus('unavailable');
      return;
    }
    if (!fix.current) setStatus('locating');
    navigator.geolocation.getCurrentPosition(
      (position) => {
        if (!enabled.current) return;
        fix.current = {
          location: {
            lat: coarse(position.coords.latitude),
            lng: coarse(position.coords.longitude),
            accuracy_m: Math.round(position.coords.accuracy),
          },
          at: Date.now(),
        };
        setStatus('on');
      },
      (error) => {
        if (!enabled.current) return;
        if (error.code === error.PERMISSION_DENIED) {
          enabled.current = false;
          fix.current = null;
          remember(false);
          setStatus('denied');
          return;
        }
        // A timeout on a refresh keeps the fix already in hand.
        if (!fix.current) setStatus('unavailable');
      },
      { enableHighAccuracy: false, maximumAge: MAX_AGE_MS, timeout: 15_000 },
    );
  }, []);

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
    if (enabled.current) {
      enabled.current = false;
      fix.current = null;
      remember(false);
      setStatus('off');
      return;
    }
    enabled.current = true;
    remember(true);
    locate();
  }, [locate]);

  const current = useCallback((): DeviceLocation | undefined => {
    if (!enabled.current || !fix.current) return undefined;
    if (Date.now() - fix.current.at > MAX_AGE_MS) locate();
    return fix.current.location;
  }, [locate]);

  return { status, toggle, current };
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
