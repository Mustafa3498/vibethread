import { z } from 'zod';

const uuid = z.string().uuid();
const page = z.coerce.number().int().min(1).default(1);
const pageSize = (max: number, def: number) => z.coerce.number().int().min(1).max(max).default(def);

export const idParam = z.object({ id: uuid });
export const variantParam = z.object({ variantId: uuid });

// ───────── cart ─────────
export const addCartItemSchema = z.object({
  variantId: uuid,
  quantity: z.coerce.number().int().min(1).max(10).default(1),
});
/** 0 removes the line. */
export const setCartItemSchema = z.object({
  quantity: z.coerce.number().int().min(0).max(10),
});

// ───────── addresses ─────────
export const addressSchema = z.object({
  label: z.string().trim().max(30).optional(),
  line1: z.string().trim().min(3).max(200),
  line2: z.string().trim().max(200).optional(),
  city: z.string().trim().min(2).max(80),
  state: z.string().trim().max(80).optional(),
  postalCode: z.string().trim().max(12).optional(),
  country: z.string().trim().length(2).default('PK'),
  isDefault: z.boolean().optional(),
});
export const updateAddressSchema = addressSchema.partial();
export type AddressInput = z.infer<typeof addressSchema>;
export type UpdateAddressInput = z.infer<typeof updateAddressSchema>;

// ───────── orders ─────────
export const placeOrderSchema = z.object({
  addressId: uuid,
  /** Only cash on delivery for now; online payment comes later. */
  paymentMethod: z.enum(['COD']).default('COD'),
  /** Needed by the courier. Saved on the user if they had none. */
  phone: z.string().trim().min(7).max(20).optional(),
});
export type PlaceOrderInput = z.infer<typeof placeOrderSchema>;

export const myOrdersQuery = z.object({ page, pageSize: pageSize(50, 10) });
export type MyOrdersQuery = z.infer<typeof myOrdersQuery>;

// ───────── staff ─────────
const ORDER_STATUSES = [
  'PENDING_PAYMENT',
  'PAID',
  'PACKING',
  'READY_TO_SHIP',
  'SHIPPED',
  'DELIVERED',
  'CANCELLED',
  'RETURNED',
] as const;

export const staffOrdersQuery = z.object({
  status: z.enum(ORDER_STATUSES).optional(),
  q: z.string().trim().min(1).max(80).optional(),
  page,
  pageSize: pageSize(100, 20),
});
export type StaffOrdersQuery = z.infer<typeof staffOrdersQuery>;

export const staffStatusSchema = z.object({
  status: z.enum(ORDER_STATUSES),
  trackingNumber: z.string().trim().min(3).max(60).optional(),
  courier: z.string().trim().min(2).max(60).optional(),
});
export type StaffStatusInput = z.infer<typeof staffStatusSchema>;
