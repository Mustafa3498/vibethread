import { Role, StockMovementType } from '@vibethread/database';
import { z } from 'zod';

// ───────── primitives ─────────
const cents = (v: number) => Math.abs(v * 100 - Math.round(v * 100)) < 1e-6;
const money = z.number().positive().max(10_000_000).refine(cents, 'Max 2 decimal places');
const uuid = z.string().uuid();
const titleCase = (s: string) =>
  s.replace(/\s+/g, ' ').split(' ').map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(' ');

const colorName = z.string().trim().min(1).max(30).transform(titleCase);
const sizeName = z.string().trim().min(1).max(10).transform((s) => s.toUpperCase());
const hex = z.string().regex(/^#[0-9a-fA-F]{6}$/, 'Use a #RRGGBB hex color');
const tag = z.string().trim().toLowerCase().min(1).max(30);
const weather = z.enum(['hot', 'mild', 'cold', 'rainy', 'humid']);
const imageUrl = z
  .string()
  .url()
  .max(2000)
  .refine((u) => u.startsWith('https://'), 'Image URL must use https');
const boolStr = z.enum(['true', 'false']).transform((v) => v === 'true');
const csv = z
  .string()
  .transform((s) => s.split(',').map((x) => x.trim()).filter(Boolean))
  .pipe(z.array(z.string()).max(20));
const page = z.coerce.number().int().min(1).default(1);
const pageSize = (max: number, def: number) => z.coerce.number().int().min(1).max(max).default(def);

export const idParam = z.object({ id: uuid });
export const variantIdParam = z.object({ variantId: uuid });
export const imageParams = z.object({ id: uuid, imageId: uuid });

// ───────── categories ─────────
export const createCategorySchema = z.object({
  name: z.string().trim().min(2).max(60),
  parentId: uuid.nullable().optional(),
  sortOrder: z.number().int().min(0).max(10_000).optional(),
});
export const updateCategorySchema = z
  .object({
    name: z.string().trim().min(2).max(60),
    parentId: uuid.nullable(),
    sortOrder: z.number().int().min(0).max(10_000),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Nothing to update');
export type CreateCategoryInput = z.infer<typeof createCategorySchema>;
export type UpdateCategoryInput = z.infer<typeof updateCategorySchema>;

// ───────── variants & images ─────────
export const variantInput = z.object({
  color: colorName,
  colorHex: hex.optional(),
  size: sizeName,
  sku: z.string().trim().toUpperCase().regex(/^[A-Z0-9-]{3,40}$/, 'SKU: A-Z, 0-9, dashes (3-40)').optional(),
  priceOverride: money.optional(),
  quantity: z.number().int().min(0).max(100_000).default(0),
  lowStockThreshold: z.number().int().min(0).max(1000).default(5),
});
export type VariantInput = z.infer<typeof variantInput>;

export const imageInput = z.object({
  url: imageUrl,
  color: colorName.optional(),
  altText: z.string().trim().max(200).optional(),
});
export type ImageInput = z.infer<typeof imageInput>;

const noDuplicateVariants = (variants: { color: string; size: string }[]) =>
  new Set(variants.map((v) => `${v.color}|${v.size}`)).size === variants.length;

export const addVariantsSchema = z.object({
  variants: z
    .array(variantInput)
    .min(1)
    .max(50)
    .refine(noDuplicateVariants, 'Duplicate color + size combination'),
});

export const updateVariantSchema = z
  .object({
    colorHex: hex.nullable(),
    priceOverride: money.nullable(),
    isActive: z.boolean(),
    lowStockThreshold: z.number().int().min(0).max(1000),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Nothing to update');
export type UpdateVariantInput = z.infer<typeof updateVariantSchema>;

export const imageOrderSchema = z.object({ imageIds: z.array(uuid).min(1).max(50) });

// ───────── products ─────────
export const createProductSchema = z
  .object({
    categoryId: uuid,
    name: z.string().trim().min(2).max(120),
    description: z.string().trim().min(1).max(5000),
    fabric: z.string().trim().max(200).optional(),
    careNotes: z.string().trim().max(1000).optional(),
    basePrice: money,
    costPrice: money.optional(),
    salePrice: money.optional(),
    promoTag: z.string().trim().max(30).optional(),
    tags: z.array(tag).max(20).default([]),
    weatherTags: z.array(weather).max(5).default([]),
    status: z.enum(['DRAFT', 'ACTIVE']).default('DRAFT'),
    images: z.array(imageInput).max(12).default([]),
    variants: z.array(variantInput).min(1).max(100),
  })
  .refine((p) => p.salePrice === undefined || p.salePrice < p.basePrice, {
    message: 'salePrice must be lower than basePrice',
    path: ['salePrice'],
  })
  .refine((p) => noDuplicateVariants(p.variants), {
    message: 'Duplicate color + size combination',
    path: ['variants'],
  });
export type CreateProductInput = z.infer<typeof createProductSchema>;

export const updateProductSchema = z
  .object({
    categoryId: uuid,
    name: z.string().trim().min(2).max(120),
    description: z.string().trim().min(1).max(5000),
    fabric: z.string().trim().max(200).nullable(),
    careNotes: z.string().trim().max(1000).nullable(),
    basePrice: money,
    costPrice: money.nullable(),
    salePrice: money.nullable(),
    promoTag: z.string().trim().max(30).nullable(),
    tags: z.array(tag).max(20),
    weatherTags: z.array(weather).max(5),
    status: z.enum(['DRAFT', 'ACTIVE']),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Nothing to update');
export type UpdateProductInput = z.infer<typeof updateProductSchema>;

// ───────── public listing ─────────
export const publicProductQuery = z.object({
  category: z.string().trim().max(80).optional(), // category slug (includes sub-categories)
  q: z.string().trim().min(1).max(80).optional(),
  minPrice: z.coerce.number().min(0).optional(),
  maxPrice: z.coerce.number().min(0).optional(),
  color: csv.optional(),
  size: csv.optional(),
  tag: csv.optional(),
  weather: weather.optional(),
  inStock: boolStr.optional(),
  sort: z.enum(['newest', 'price_asc', 'price_desc', 'trending']).default('newest'),
  page,
  pageSize: pageSize(48, 12),
});
export type PublicProductQuery = z.infer<typeof publicProductQuery>;

export const manageProductQuery = z.object({
  q: z.string().trim().min(1).max(80).optional(),
  status: z.enum(['DRAFT', 'ACTIVE', 'ARCHIVED']).optional(),
  categoryId: uuid.optional(),
  page,
  pageSize: pageSize(100, 20),
});
export type ManageProductQuery = z.infer<typeof manageProductQuery>;

// ───────── inventory ─────────
export const inventoryListQuery = z.object({
  q: z.string().trim().min(1).max(80).optional(),
  lowStock: boolStr.optional(),
  outOfStock: boolStr.optional(),
  page,
  pageSize: pageSize(100, 25),
});
export type InventoryListQuery = z.infer<typeof inventoryListQuery>;

export const stockAdjustSchema = z
  .object({
    delta: z.number().int().min(-100_000).max(100_000).refine((n) => n !== 0, 'delta cannot be 0').optional(),
    setQuantity: z.number().int().min(0).max(1_000_000).optional(),
    type: z.enum(['RESTOCK', 'ADJUSTMENT']).optional(),
    reason: z.string().trim().max(200).optional(),
  })
  .refine((o) => (o.delta === undefined) !== (o.setQuantity === undefined), {
    message: 'Send exactly one of delta or setQuantity',
  });
export type StockAdjustInput = z.infer<typeof stockAdjustSchema>;

export const movementsQuery = z.object({
  variantId: uuid.optional(),
  type: z.nativeEnum(StockMovementType).optional(),
  page,
  pageSize: pageSize(100, 25),
});

export const alertsQuery = z.object({ unread: boolStr.optional(), page, pageSize: pageSize(100, 25) });

export { Role };
