/** One size/price row as the items endpoint sends it (`variants[]`). */
export interface ItemVariant {
  size: string | null;
  /** In the currency's minor unit (cents for USD, yen for JPY). */
  price_cents: number | null;
  currency: string | null;
}

/** Minor units per major unit: 100 for USD, 1 for JPY. Null if unknown. */
function minorDigits(currency: string): number | null {
  try {
    return (
      new Intl.NumberFormat('en-US', { style: 'currency', currency }).resolvedOptions()
        .maximumFractionDigits ?? 2
    );
  } catch {
    return null;
  }
}

function formatAmount(amount: number, currency: string, digits: number, known: boolean): string {
  if (!known) return `${amount.toFixed(digits)} ${currency}`;
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(amount);
}

/**
 * The price chip text for a dish: "$12", "$12.50", or "$9–$14" across
 * sizes. Unpriced and zero-priced sizes are skipped, and only sizes in
 * the first priced size's currency count. Null when nothing is priced.
 */
export function formatPriceRange(variants: ItemVariant[] | undefined): string | null {
  const priced = (variants ?? []).filter(
    (v): v is ItemVariant & { price_cents: number } =>
      typeof v.price_cents === 'number' && v.price_cents > 0,
  );
  const first = priced[0];
  if (!first) return null;

  const currency = (first.currency || 'USD').toUpperCase();
  const minor = priced
    .filter((v) => (v.currency || 'USD').toUpperCase() === currency)
    .map((v) => v.price_cents);
  const low = Math.min(...minor);
  const high = Math.max(...minor);

  const known = minorDigits(currency);
  const scale = 10 ** (known ?? 2);
  // Whole amounts drop the fraction; if either end has one, both show it.
  const digits = low % scale === 0 && high % scale === 0 ? 0 : (known ?? 2);
  const lowText = formatAmount(low / scale, currency, digits, known !== null);
  if (low === high) return lowText;
  return `${lowText}–${formatAmount(high / scale, currency, digits, known !== null)}`;
}
