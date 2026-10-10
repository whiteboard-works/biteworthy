import { describe, expect, it } from 'vitest';
import { formatPriceRange } from './price';

/**
 * The price chip on dish cards. Diners read it to decide whether to
 * order, so a missing or unparseable price must show nothing rather
 * than a guess like "$0".
 */
describe('formatPriceRange', () => {
  it('shows whole dollars without cents', () => {
    expect(formatPriceRange([{ size: null, price_cents: 1200, currency: 'USD' }])).toBe('$12');
  });

  it('keeps cents when the price has them', () => {
    expect(formatPriceRange([{ size: null, price_cents: 1250, currency: 'USD' }])).toBe('$12.50');
  });

  it('shows the low–high range across sizes, in any order', () => {
    expect(
      formatPriceRange([
        { size: 'Full', price_cents: 1400, currency: 'USD' },
        { size: 'Half', price_cents: 900, currency: 'USD' },
      ]),
    ).toBe('$9–$14');
  });

  it('collapses sizes that cost the same to one price', () => {
    expect(
      formatPriceRange([
        { size: 'Red', price_cents: 1000, currency: 'USD' },
        { size: 'Green', price_cents: 1000, currency: 'USD' },
      ]),
    ).toBe('$10');
  });

  it('ignores sizes with no price ("market price") instead of treating them as free', () => {
    expect(
      formatPriceRange([
        { size: 'Large', price_cents: null, currency: 'USD' },
        { size: 'Small', price_cents: 800, currency: 'USD' },
      ]),
    ).toBe('$8');
  });

  it('returns null when no size has a price, so no chip renders', () => {
    expect(formatPriceRange([{ size: 'Market', price_cents: null, currency: 'USD' }])).toBeNull();
    expect(formatPriceRange([])).toBeNull();
    expect(formatPriceRange(undefined)).toBeNull();
  });

  it("uses the dish's own currency, defaulting to USD when unset", () => {
    expect(formatPriceRange([{ size: null, price_cents: 900, currency: 'EUR' }])).toBe('€9');
    expect(formatPriceRange([{ size: null, price_cents: 900, currency: null }])).toBe('$9');
  });

  it('treats a zero price as unpriced, never "$0"', () => {
    expect(formatPriceRange([{ size: 'Market', price_cents: 0, currency: 'USD' }])).toBeNull();
    expect(
      formatPriceRange([
        { size: 'Small', price_cents: 0, currency: 'USD' },
        { size: 'Large', price_cents: 1400, currency: 'USD' },
      ]),
    ).toBe('$14');
  });

  it('formats both ends of a range alike when either has cents', () => {
    expect(
      formatPriceRange([
        { size: 'Half', price_cents: 900, currency: 'USD' },
        { size: 'Full', price_cents: 1450, currency: 'USD' },
      ]),
    ).toBe('$9.00–$14.50');
  });

  // price_cents is in the currency's minor unit; yen has none.
  it('does not divide by 100 for a currency without a minor unit', () => {
    expect(formatPriceRange([{ size: null, price_cents: 1200, currency: 'JPY' }])).toBe('¥1,200');
  });

  it('does not mix currencies into one range', () => {
    expect(
      formatPriceRange([
        { size: 'A', price_cents: 900, currency: 'USD' },
        { size: 'B', price_cents: 50000, currency: 'JPY' },
      ]),
    ).toBe('$9');
  });

  it('falls back to the raw code for a currency the runtime does not know', () => {
    expect(formatPriceRange([{ size: null, price_cents: 1250, currency: 'zz' }])).toBe('12.50 ZZ');
  });
});
