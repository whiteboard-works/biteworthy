/** One size/price row as the items endpoint sends it (`variants[]`). */
export interface ItemVariant {
  size: string | null;
  price_cents: number | null;
  currency: string | null;
}

function formatAmount(cents: number, currency: string): string {
  const whole = cents % 100 === 0;
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency,
      minimumFractionDigits: whole ? 0 : 2,
      maximumFractionDigits: whole ? 0 : 2,
    }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(whole ? 0 : 2)} ${currency}`;
  }
}

/**
 * The price chip text for a dish: "$12", "$12.50", or "$9–$14" across
 * sizes. Sizes without a price are skipped, and only sizes in the
 * first priced size's currency count. Null when nothing is priced.
 */
export function formatPriceRange(variants: ItemVariant[] | undefined): string | null {
  const priced = (variants ?? []).filter(
    (v): v is ItemVariant & { price_cents: number } => typeof v.price_cents === 'number',
  );
  const first = priced[0];
  if (!first) return null;

  const currency = (first.currency || 'USD').toUpperCase();
  const cents = priced
    .filter((v) => (v.currency || 'USD').toUpperCase() === currency)
    .map((v) => v.price_cents);
  const low = Math.min(...cents);
  const high = Math.max(...cents);
  const lowText = formatAmount(low, currency);
  return low === high ? lowText : `${lowText}–${formatAmount(high, currency)}`;
}
