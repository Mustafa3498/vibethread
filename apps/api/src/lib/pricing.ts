import type { Prisma } from '@vibethread/database';

/** Checkout stock hold. After this the job releases the units again. */
export const HOLD_MINUTES = 15;
export const MAX_QTY_PER_LINE = 10;

/** Flat shipping (PKR). Free above the threshold. */
export const SHIPPING_FLAT_FEE = 250;
export const FREE_SHIPPING_OVER = 5000;

export const round2 = (n: number) => Math.round(n * 100) / 100;

export const toNum = (d: Prisma.Decimal | number | null | undefined): number | null =>
  d === null || d === undefined ? null : Number(d);

/** priceOverride wins, then the product's sale price, then base price. */
export function unitPriceOf(
  product: { basePrice: Prisma.Decimal; salePrice: Prisma.Decimal | null },
  variant: { priceOverride: Prisma.Decimal | null },
): number {
  return Number(variant.priceOverride ?? product.salePrice ?? product.basePrice);
}

export const shippingFeeFor = (subtotal: number) =>
  subtotal <= 0 || subtotal >= FREE_SHIPPING_OVER ? 0 : SHIPPING_FLAT_FEE;

/** Karachi 2 days, rest of the country 4 days. Drives the delivery countdown clock. */
export function estimatedDeliveryFor(city: string, from = new Date()): Date {
  const days = city.trim().toLowerCase() === 'karachi' ? 2 : 4;
  return new Date(from.getTime() + days * 24 * 60 * 60 * 1000);
}
