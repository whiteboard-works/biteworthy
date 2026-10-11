/**
 * Restaurant hours utilities for computing open/closed status.
 * Status is computed in the restaurant's timezone, not the viewer's.
 */

export interface HourInterval {
  day_of_week: number; // 0=Sunday, 6=Saturday
  opens_at: string | null; // "HH:MM" or null for closed
  closes_at: string | null; // "HH:MM" or null for closed
}

export interface OpenStatus {
  isOpen: boolean;
  nextChange: string | null; // Human-readable: "Closes 9:00 PM", "Opens 11:00 AM tomorrow"
  isClosingSoon: boolean; // True if closing within 30 minutes
}

/**
 * Parse HH:MM time string to minutes since midnight.
 * Returns null if the input is null or invalid.
 */
function parseTime(time: string | null): number | null {
  if (!time) return null;
  const match = time.match(/^(\d{2}):(\d{2})$/);
  if (!match) return null;
  const hours = parseInt(match[1]!, 10);
  const minutes = parseInt(match[2]!, 10);
  return hours * 60 + minutes;
}

/**
 * Format minutes since midnight as "h:MM AM/PM".
 */
function formatTime(minutes: number): string {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  const period = hours >= 12 ? 'PM' : 'AM';
  const displayHours = hours === 0 ? 12 : hours > 12 ? hours - 12 : hours;
  return `${displayHours}:${mins.toString().padStart(2, '0')} ${period}`;
}

/**
 * Get the current time in the given IANA timezone.
 * Returns { dayOfWeek: 0-6, minutesSinceMidnight: number }.
 */
function getCurrentTime(timeZone: string | null): { dayOfWeek: number; minutes: number } {
  const now = new Date();
  // If no timezone, fall back to browser time
  const tz = timeZone ?? undefined;

  try {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      weekday: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });

    const parts = formatter.formatToParts(now);
    const dayName = parts.find((p) => p.type === 'weekday')?.value;
    const hour = parseInt(parts.find((p) => p.type === 'hour')?.value ?? '0', 10);
    const minute = parseInt(parts.find((p) => p.type === 'minute')?.value ?? '0', 10);

    const dayMap: Record<string, number> = {
      Sun: 0,
      Mon: 1,
      Tue: 2,
      Wed: 3,
      Thu: 4,
      Fri: 5,
      Sat: 6,
    };
    const dayOfWeek = dayMap[dayName ?? 'Sun'] ?? 0;

    return {
      dayOfWeek,
      minutes: hour * 60 + minute,
    };
  } catch {
    // Fallback if timezone is invalid
    const dayOfWeek = now.getDay();
    const minutes = now.getHours() * 60 + now.getMinutes();
    return { dayOfWeek, minutes };
  }
}

/**
 * Compute the current open/closed status for a restaurant.
 * Handles overnight intervals (closes_at < opens_at means closes next day),
 * split shifts, closed days, and "closes soon" within 30 minutes.
 */
export function getOpenStatus(
  hours: HourInterval[],
  timeZone: string | null,
): OpenStatus | null {
  if (hours.length === 0) {
    return null; // No hours available
  }

  const { dayOfWeek, minutes } = getCurrentTime(timeZone);

  // Filter intervals for today
  const todayIntervals = hours.filter((h) => h.day_of_week === dayOfWeek);

  // Check if currently open
  for (const interval of todayIntervals) {
    const opens = parseTime(interval.opens_at);
    const closes = parseTime(interval.closes_at);

    if (opens === null || closes === null) continue;

    // Handle overnight: if closes < opens, the interval spans midnight
    const isOvernight = closes < opens;

    if (isOvernight) {
      // Open from opens until midnight, or from midnight until closes
      if (minutes >= opens || minutes < closes) {
        const closingSoon = closes > minutes && closes - minutes <= 30;
        return {
          isOpen: true,
          nextChange: `Closes ${formatTime(closes)}`,
          isClosingSoon: closingSoon,
        };
      }
    } else {
      // Normal interval within the same day
      if (minutes >= opens && minutes < closes) {
        const closingSoon = closes - minutes <= 30;
        return {
          isOpen: true,
          nextChange: `Closes ${formatTime(closes)}`,
          isClosingSoon: closingSoon,
        };
      }
    }
  }

  // Not currently open — find the next opening
  // First, check later today
  for (const interval of todayIntervals) {
    const opens = parseTime(interval.opens_at);
    if (opens !== null && opens > minutes) {
      return {
        isOpen: false,
        nextChange: `Opens ${formatTime(opens)}`,
        isClosingSoon: false,
      };
    }
  }

  // Check if we're in an overnight interval from yesterday
  const yesterday = (dayOfWeek + 6) % 7;
  const yesterdayIntervals = hours.filter((h) => h.day_of_week === yesterday);
  for (const interval of yesterdayIntervals) {
    const opens = parseTime(interval.opens_at);
    const closes = parseTime(interval.closes_at);
    if (opens !== null && closes !== null && closes < opens && minutes < closes) {
      const closingSoon = closes - minutes <= 30;
      return {
        isOpen: true,
        nextChange: `Closes ${formatTime(closes)}`,
        isClosingSoon: closingSoon,
      };
    }
  }

  // No more openings today — find the next opening on a future day
  for (let i = 1; i <= 7; i++) {
    const futureDay = (dayOfWeek + i) % 7;
    const futureIntervals = hours
      .filter((h) => h.day_of_week === futureDay)
      .sort((a, b) => {
        const aOpens = parseTime(a.opens_at) ?? 0;
        const bOpens = parseTime(b.opens_at) ?? 0;
        return aOpens - bOpens;
      });

    if (futureIntervals.length > 0) {
      const firstInterval = futureIntervals[0]!;
      const opens = parseTime(firstInterval.opens_at);
      if (opens !== null) {
        const dayName = i === 1 ? 'tomorrow' : ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][futureDay];
        return {
          isOpen: false,
          nextChange: `Opens ${formatTime(opens)} ${dayName}`,
          isClosingSoon: false,
        };
      }
    }
  }

  // No valid hours found
  return {
    isOpen: false,
    nextChange: null,
    isClosingSoon: false,
  };
}

/**
 * Format hours for display in a weekly grid.
 * Returns an array of 7 days (Sunday-Saturday) with their intervals.
 */
export function formatWeeklyHours(hours: HourInterval[]): Array<{
  day: string;
  dayOfWeek: number;
  intervals: Array<{ opens: string; closes: string }> | null;
}> {
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  return dayNames.map((day, dayOfWeek) => {
    const dayIntervals = hours
      .filter((h) => h.day_of_week === dayOfWeek)
      .map((h) => {
        const opens = h.opens_at ? formatTime(parseTime(h.opens_at)!) : null;
        const closes = h.closes_at ? formatTime(parseTime(h.closes_at)!) : null;
        return opens && closes ? { opens, closes } : null;
      })
      .filter((i): i is { opens: string; closes: string } => i !== null);

    return {
      day,
      dayOfWeek,
      intervals: dayIntervals.length > 0 ? dayIntervals : null,
    };
  });
}
