import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { getOpenStatus, formatWeeklyHours, type HourInterval } from '../hours';

describe('getOpenStatus', () => {
  beforeEach(() => {
    // Mock the current time to Tuesday 2:30 PM (14:30) in America/Denver
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2024-01-09T21:30:00.000Z')); // 2:30 PM Denver = 9:30 PM UTC
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns null when no hours exist', () => {
    const status = getOpenStatus([], 'America/Denver');
    expect(status).toBeNull();
  });

  it('returns open status when currently open', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '11:00', closes_at: '21:00' }, // Tuesday 11 AM - 9 PM
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(true);
    expect(status?.nextChange).toContain('Closes');
    expect(status?.isClosingSoon).toBe(false);
  });

  it('detects closing soon within 30 minutes', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '11:00', closes_at: '14:45' }, // Tuesday, closes at 2:45 PM
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(true);
    expect(status?.isClosingSoon).toBe(true);
  });

  it('returns closed status when currently closed', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '17:00', closes_at: '21:00' }, // Tuesday 5 PM - 9 PM (not open yet)
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(false);
    expect(status?.nextChange).toContain('Opens');
  });

  it('handles overnight intervals that close after midnight', () => {
    // Current time: Tuesday 2:30 PM
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '22:00', closes_at: '02:00' }, // Tuesday 10 PM - 2 AM
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(false);
  });

  it('detects open status when in overnight interval', () => {
    // Mock Wednesday 1:00 AM (still within Tuesday's overnight shift)
    vi.setSystemTime(new Date('2024-01-10T08:00:00.000Z')); // 1:00 AM Denver

    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '22:00', closes_at: '02:00' }, // Tuesday 10 PM - 2 AM
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(true);
    expect(status?.nextChange).toContain('Closes 2:00 AM');
  });

  it('handles split shifts (multiple intervals per day)', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '11:00', closes_at: '14:00' }, // Lunch
      { day_of_week: 2, opens_at: '17:00', closes_at: '21:00' }, // Dinner
    ];

    // 2:30 PM - between shifts
    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(false);
    expect(status?.nextChange).toContain('Opens 5:00 PM');
  });

  it('handles closed days with null times', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: null, closes_at: null }, // Tuesday closed
      { day_of_week: 3, opens_at: '11:00', closes_at: '21:00' }, // Wednesday open
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(false);
    expect(status?.nextChange).toContain('Opens');
    expect(status?.nextChange).toContain('tomorrow'); // Opens Wednesday (tomorrow)
  });

  it('finds next opening on a future day', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '11:00', closes_at: '13:00' }, // Tuesday 11 AM - 1 PM (already closed)
      { day_of_week: 4, opens_at: '11:00', closes_at: '21:00' }, // Thursday
    ];

    const status = getOpenStatus(hours, 'America/Denver');
    expect(status).toBeDefined();
    expect(status?.isOpen).toBe(false);
    expect(status?.nextChange).toContain('Thursday');
  });

  it('handles missing timezone by falling back to browser time', () => {
    const hours: HourInterval[] = [
      { day_of_week: 2, opens_at: '11:00', closes_at: '21:00' },
    ];

    // Should not throw and should return a status
    const status = getOpenStatus(hours, null);
    expect(status).toBeDefined();
  });
});

describe('formatWeeklyHours', () => {
  it('formats a full week of hours', () => {
    const hours: HourInterval[] = [
      { day_of_week: 0, opens_at: '12:00', closes_at: '20:00' }, // Sunday
      { day_of_week: 1, opens_at: '11:00', closes_at: '21:00' }, // Monday
      { day_of_week: 2, opens_at: '11:00', closes_at: '21:00' }, // Tuesday
      { day_of_week: 3, opens_at: '11:00', closes_at: '21:00' }, // Wednesday
      { day_of_week: 4, opens_at: '11:00', closes_at: '21:00' }, // Thursday
      { day_of_week: 5, opens_at: '11:00', closes_at: '22:00' }, // Friday
      { day_of_week: 6, opens_at: '11:00', closes_at: '22:00' }, // Saturday
    ];

    const formatted = formatWeeklyHours(hours);
    expect(formatted).toHaveLength(7);
    expect(formatted[0]?.day).toBe('Sunday');
    expect(formatted[0]?.intervals).toHaveLength(1);
    expect(formatted[0]?.intervals?.[0]).toEqual({
      opens: '12:00 PM',
      closes: '8:00 PM',
    });
  });

  it('marks closed days with null intervals', () => {
    const hours: HourInterval[] = [
      { day_of_week: 1, opens_at: '11:00', closes_at: '21:00' }, // Monday open
      // Tuesday has no entry
    ];

    const formatted = formatWeeklyHours(hours);
    expect(formatted[2]?.day).toBe('Tuesday');
    expect(formatted[2]?.intervals).toBeNull();
  });

  it('handles split shifts correctly', () => {
    const hours: HourInterval[] = [
      { day_of_week: 1, opens_at: '11:00', closes_at: '14:00' }, // Monday lunch
      { day_of_week: 1, opens_at: '17:00', closes_at: '21:00' }, // Monday dinner
    ];

    const formatted = formatWeeklyHours(hours);
    expect(formatted[1]?.day).toBe('Monday');
    expect(formatted[1]?.intervals).toHaveLength(2);
    expect(formatted[1]?.intervals?.[0]).toEqual({
      opens: '11:00 AM',
      closes: '2:00 PM',
    });
    expect(formatted[1]?.intervals?.[1]).toEqual({
      opens: '5:00 PM',
      closes: '9:00 PM',
    });
  });

  it('handles overnight hours', () => {
    const hours: HourInterval[] = [
      { day_of_week: 5, opens_at: '22:00', closes_at: '02:00' }, // Friday night to Saturday morning
    ];

    const formatted = formatWeeklyHours(hours);
    expect(formatted[5]?.day).toBe('Friday');
    expect(formatted[5]?.intervals?.[0]).toEqual({
      opens: '10:00 PM',
      closes: '2:00 AM',
    });
  });

  it('filters out intervals with null times', () => {
    const hours: HourInterval[] = [
      { day_of_week: 1, opens_at: '11:00', closes_at: '21:00' }, // Valid
      { day_of_week: 2, opens_at: null, closes_at: null }, // Closed
    ];

    const formatted = formatWeeklyHours(hours);
    expect(formatted[1]?.intervals).toHaveLength(1);
    expect(formatted[2]?.intervals).toBeNull();
  });
});
