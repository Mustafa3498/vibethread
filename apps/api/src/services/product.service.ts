import { randomBytes } from 'node:crypto';
import { Prisma, prisma, ProductStatus, Role, StockMovementType } from '@vibethread/database';
import { SOCKET_EVENTS, SOCKET_ROOMS, type ProductUpdatedPayload } from '@vibethread/shared';
import { Errors } from '../lib/errors';
import { compareSizes, num, paginated } from '../lib/serialize';
import { uniqueSlug } from '../lib/slug';
import { emitToRoom } from '../realtime/emitters';
import type {
  CreateProductInput,
  ImageInput,
  ManageProductQuery,
  PublicProductQuery,
  UpdateProductInput,
  UpdateVariantInput,
  VariantInput,
} from '../schemas/catalog';
import { categoryIdsWithDescendants } from './category.service';

type Tx = Prisma.TransactionClient;
export interface Actor {
  userId: string;
  role: Role;
}

const productInclude = {
  category: { select: { id: true, name: true, slug: true } },
  images: { orderBy: { sortOrder: 'asc' } },
  variants: { include: { inventory: true } },
} satisfies Prisma.ProductInclude;
type FullProduct = Prisma.ProductGetPayload<{ include: typeof productInclude }>;
type FullVariant = FullProduct['variants'][number];

// ───────────────────────── serializers ─────────────────────────

const availableOf = (v: FullVariant) => (v.inventory ? Math.max(v.inventory.quantity - v.inventory.reserved, 0) : 0);
const sortVariants = (vs: FullVariant[]) =>
  [...vs].sort((a, b) => a.color.localeCompare(b.color) || compareSizes(a.size, b.size));
/** priceOverride wins, then the product's sale price, then base price. */
const priceOf = (p: FullProduct, v: { priceOverride: Prisma.Decimal | null }) =>
  num(v.priceOverride ?? p.salePrice ?? p.basePrice)!;

function colorsAndSizes(variants: FullVariant[]) {
  const colors = new Map<string, string | null>();
  const sizes = new Set<string>();
  for (const v of variants) {
    if (!colors.has(v.color)) colors.set(v.color, v.colorHex);
    sizes.add(v.size);
  }
  return {
    colors: [...colors].map(([color, colorHex]) => ({ color, colorHex })),
    sizes: [...sizes].sort(compareSizes),
  };
}

/** Everything a shopper may see. Never includes cost price or exact stock numbers. */
export function toPublicProduct(p: FullProduct) {
  const active = sortVariants(p.variants.filter((v) => v.isActive));
  return {
    id: p.id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    fabric: p.fabric,
    careNotes: p.careNotes,
    category: p.category,
    basePrice: num(p.basePrice),
    salePrice: num(p.salePrice),
    promoTag: p.promoTag,
    tags: p.tags,
    weatherTags: p.weatherTags,
    images: p.images.map((i) => ({ id: i.id, url: i.url, color: i.color, altText: i.altText })),
    ...colorsAndSizes(active),
    variants: active.map((v) => {
      const available = availableOf(v);
      return {
        id: v.id,
        sku: v.sku,
        color: v.color,
        colorHex: v.colorHex,
        size: v.size,
        price: priceOf(p, v),
        available,
        inStock: available > 0,
        lowStock: available > 0 && available <= (v.inventory?.lowStockThreshold ?? 5),
      };
    }),
    createdAt: p.createdAt.toISOString(),
  };
}

export function toProductCard(p: FullProduct) {
  const active = p.variants.filter((v) => v.isActive);
  const prices = active.map((v) => priceOf(p, v));
  const availables = active.map(availableOf);
  return {
    id: p.id,
    name: p.name,
    slug: p.slug,
    category: p.category,
    promoTag: p.promoTag,
    basePrice: num(p.basePrice),
    salePrice: num(p.salePrice),
    price: prices.length ? Math.min(...prices) : num(p.salePrice ?? p.basePrice),
    thumbnail: p.images[0]?.url ?? null,
    ...colorsAndSizes(active),
    inStock: availables.some((a) => a > 0),
    lowStock: availables.some((a, i) => a > 0 && a <= (active[i]!.inventory?.lowStockThreshold ?? 5)),
  };
}

/** Staff view. costPrice is ADMIN-only. */
export function toStaffProduct(p: FullProduct, role: Role) {
  const variants = sortVariants(p.variants).map((v) => {
    const quantity = v.inventory?.quantity ?? 0;
    const reserved = v.inventory?.reserved ?? 0;
    return {
      id: v.id,
      sku: v.sku,
      color: v.color,
      colorHex: v.colorHex,
      size: v.size,
      priceOverride: num(v.priceOverride),
      effectivePrice: priceOf(p, v),
      isActive: v.isActive,
      quantity,
      reserved,
      available: Math.max(quantity - reserved, 0),
      lowStockThreshold: v.inventory?.lowStockThreshold ?? 0,
    };
  });
  return {
    id: p.id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    fabric: p.fabric,
    careNotes: p.careNotes,
    category: p.category,
    status: p.status,
    basePrice: num(p.basePrice),
    salePrice: num(p.salePrice),
    ...(role === Role.ADMIN ? { costPrice: num(p.costPrice) } : {}),
    promoTag: p.promoTag,
    tags: p.tags,
    weatherTags: p.weatherTags,
    images: p.images.map((i) => ({ id: i.id, url: i.url, color: i.color, altText: i.altText, sortOrder: i.sortOrder })),
    variants,
    totalAvailable: variants.filter((v) => v.isActive).reduce((s, v) => s + v.available, 0),
    archivedAt: p.archivedAt?.toISOString() ?? null,
    createdAt: p.createdAt.toISOString(),
    updatedAt: p.updatedAt.toISOString(),
  };
}

// ───────────────────────── public catalog ─────────────────────────

export async function listPublicProducts(q: PublicProductQuery) {
  const and: Prisma.ProductWhereInput[] = [{ status: ProductStatus.ACTIVE }];

  if (q.category) {
    const ids = await categoryIdsWithDescendants(q.category);
    if (!ids) return paginated([], 0, q.page, q.pageSize);
    and.push({ categoryId: { in: ids } });
  }
  if (q.q) {
    and.push({
      OR: [
        { name: { contains: q.q, mode: 'insensitive' } },
        { description: { contains: q.q, mode: 'insensitive' } },
        { tags: { has: q.q.toLowerCase() } },
      ],
    });
  }
  if (q.minPrice !== undefined || q.maxPrice !== undefined) {
    const range = { gte: q.minPrice, lte: q.maxPrice };
    // effective price = salePrice if set, else basePrice
    and.push({ OR: [{ salePrice: { not: null, ...range } }, { salePrice: null, basePrice: range }] });
  }
  if (q.tag?.length) and.push({ tags: { hasSome: q.tag.map((t) => t.toLowerCase()) } });
  if (q.weather) and.push({ weatherTags: { has: q.weather } });

  const variantFilter: Prisma.ProductVariantWhereInput = { isActive: true };
  if (q.color?.length) variantFilter.OR = q.color.map((c) => ({ color: { equals: c, mode: 'insensitive' } }));
  if (q.size?.length) variantFilter.size = { in: q.size.map((s) => s.toUpperCase()) };
  if (q.color?.length || q.size?.length) and.push({ variants: { some: variantFilter } });

  if (q.inStock) {
    const rows = await prisma.$queryRaw<{ productId: string }[]>`
      SELECT DISTINCT v."productId" FROM "ProductVariant" v
      JOIN "Inventory" i ON i."variantId" = v.id
      WHERE v."isActive" = true AND i.quantity - i.reserved > 0`;
    and.push({ id: { in: rows.map((r) => r.productId) } });
  }

  const orderBy: Prisma.ProductOrderByWithRelationInput[] =
    q.sort === 'price_asc' ? [{ basePrice: 'asc' }]
    : q.sort === 'price_desc' ? [{ basePrice: 'desc' }]
    : q.sort === 'trending' ? [{ trendScore: 'desc' }, { createdAt: 'desc' }]
    : [{ createdAt: 'desc' }];

  const where: Prisma.ProductWhereInput = { AND: and };
  const [total, rows] = await Promise.all([
    prisma.product.count({ where }),
    prisma.product.findMany({
      where,
      orderBy,
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
      include: { ...productInclude, images: { orderBy: { sortOrder: 'asc' }, take: 1 } },
    }),
  ]);
  return paginated(rows.map(toProductCard), total, q.page, q.pageSize);
}

export async function getPublicProduct(slug: string) {
  const p = await prisma.product.findFirst({
    where: { slug, status: ProductStatus.ACTIVE },
    include: productInclude,
  });
  if (!p) throw Errors.notFound('Product not found');
  return toPublicProduct(p);
}

// ───────────────────────── staff: read ─────────────────────────

export async function listStaffProducts(q: ManageProductQuery, role: Role) {
  const where: Prisma.ProductWhereInput = {
    status: q.status,
    categoryId: q.categoryId,
    ...(q.q
      ? {
          OR: [
            { name: { contains: q.q, mode: 'insensitive' } },
            { variants: { some: { sku: { contains: q.q, mode: 'insensitive' } } } },
          ],
        }
      : {}),
  };
  const [total, rows] = await Promise.all([
    prisma.product.count({ where }),
    prisma.product.findMany({
      where,
      include: productInclude,
      orderBy: { updatedAt: 'desc' },
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
    }),
  ]);
  return paginated(rows.map((p) => toStaffProduct(p, role)), total, q.page, q.pageSize);
}

export async function getStaffProduct(id: string, role: Role) {
  return toStaffProduct(await loadProduct(prisma, id), role);
}

async function loadProduct(db: Tx | typeof prisma, id: string): Promise<FullProduct> {
  const p = await db.product.findUnique({ where: { id }, include: productInclude });
  if (!p) throw Errors.notFound('Product not found');
  return p;
}

// ───────────────────────── staff: create ─────────────────────────

export async function createProduct(input: CreateProductInput, actor: Actor) {
  if (input.costPrice !== undefined && actor.role !== Role.ADMIN) {
    throw Errors.forbidden('Only admins can set the cost price');
  }
  if (input.status === 'ACTIVE' && input.images.length === 0) {
    throw Errors.badRequest('Add at least one image before publishing (or save as DRAFT)');
  }
  const category = await prisma.category.findUnique({ where: { id: input.categoryId } });
  if (!category) throw Errors.badRequest('Category does not exist');

  try {
    const id = await prisma.$transaction(async (tx) => {
      const slug = await uniqueSlug(async (s) => !!(await tx.product.findUnique({ where: { slug: s }, select: { id: true } })), input.name);
      const skus = await resolveSkus(tx, slug, input.variants);

      const product = await tx.product.create({
        data: {
          categoryId: input.categoryId,
          name: input.name,
          slug,
          description: input.description,
          fabric: input.fabric,
          careNotes: input.careNotes,
          basePrice: input.basePrice,
          costPrice: input.costPrice,
          salePrice: input.salePrice,
          promoTag: input.promoTag,
          tags: input.tags,
          weatherTags: input.weatherTags,
          status: input.status,
          images: { create: input.images.map((img, i) => ({ url: img.url, color: img.color, altText: img.altText, sortOrder: i })) },
          variants: {
            create: input.variants.map((v, i) => ({
              sku: skus[i]!,
              color: v.color,
              colorHex: v.colorHex,
              size: v.size,
              priceOverride: v.priceOverride,
              inventory: { create: { quantity: v.quantity, lowStockThreshold: v.lowStockThreshold } },
            })),
          },
        },
        include: { variants: { select: { id: true, sku: true } } },
      });
      await recordInitialStock(tx, product.variants, input.variants, skus, actor.userId);
      return product.id;
    });
    return toStaffProduct(await loadProduct(prisma, id), actor.role);
  } catch (err) {
    throw mapUnique(err);
  }
}

async function recordInitialStock(
  tx: Tx,
  created: { id: string; sku: string }[],
  inputs: VariantInput[],
  skus: string[],
  actorId: string,
) {
  const qtyBySku = new Map(skus.map((sku, i) => [sku, inputs[i]!.quantity]));
  const data = created
    .filter((v) => (qtyBySku.get(v.sku) ?? 0) > 0)
    .map((v) => ({ variantId: v.id, type: StockMovementType.RESTOCK, delta: qtyBySku.get(v.sku)!, reason: 'Initial stock', actorId }));
  if (data.length) await tx.stockMovement.createMany({ data });
}

/** Explicit SKUs are validated; missing ones are generated as PREFIX-COL-SIZE (+ random suffix on clash). */
async function resolveSkus(tx: Tx, productSlug: string, variants: VariantInput[]): Promise<string[]> {
  const explicit = variants.map((v) => v.sku).filter((s): s is string => !!s);
  if (new Set(explicit).size !== explicit.length) throw Errors.badRequest('Duplicate SKU in request');
  if (explicit.length) {
    const taken = await tx.productVariant.findMany({ where: { sku: { in: explicit } }, select: { sku: true } });
    if (taken.length) throw Errors.conflict(`SKU already in use: ${taken.map((t) => t.sku).join(', ')}`);
  }
  const used = new Set(explicit);
  const prefix = productSlug.replace(/-/g, '').slice(0, 6).toUpperCase() || 'ITEM';
  const out: string[] = [];
  for (const v of variants) {
    if (v.sku) {
      out.push(v.sku);
      continue;
    }
    const base = `${prefix}-${v.color.replace(/[^a-z0-9]/gi, '').slice(0, 3).toUpperCase()}-${v.size.replace(/[^A-Z0-9]/g, '')}`;
    let sku = base;
    while (used.has(sku) || (await tx.productVariant.findUnique({ where: { sku }, select: { id: true } }))) {
      sku = `${base}-${randomBytes(2).toString('hex').toUpperCase()}`;
    }
    used.add(sku);
    out.push(sku);
  }
  return out;
}

function mapUnique(err: unknown) {
  if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
    return Errors.conflict('A product or SKU with the same unique value already exists');
  }
  return err;
}

// ───────────────────────── staff: update / lifecycle ─────────────────────────

export async function updateProduct(id: string, input: UpdateProductInput, actor: Actor) {
  if (input.costPrice !== undefined && actor.role !== Role.ADMIN) {
    throw Errors.forbidden('Only admins can change the cost price');
  }
  const current = await loadProduct(prisma, id);

  const basePrice = input.basePrice ?? num(current.basePrice)!;
  const salePrice = input.salePrice !== undefined ? input.salePrice : num(current.salePrice);
  if (salePrice !== null && salePrice >= basePrice) throw Errors.badRequest('salePrice must be lower than basePrice');

  if (input.categoryId && input.categoryId !== current.categoryId) {
    if (!(await prisma.category.findUnique({ where: { id: input.categoryId } }))) {
      throw Errors.badRequest('Category does not exist');
    }
  }
  if (input.status) {
    if (current.status === ProductStatus.ARCHIVED) throw Errors.conflict('Restore this product before changing its status');
    if (input.status === 'ACTIVE') assertPublishable(current);
  }

  await prisma.product.update({ where: { id }, data: input });
  const updated = await loadProduct(prisma, id);
  announceProduct(updated);
  return toStaffProduct(updated, actor.role);
}

function assertPublishable(p: FullProduct) {
  if (p.images.length === 0) throw Errors.badRequest('Add at least one image before publishing');
  if (!p.variants.some((v) => v.isActive)) throw Errors.badRequest('Add at least one active variant before publishing');
}

export async function archiveProduct(id: string, actor: Actor) {
  await loadProduct(prisma, id);
  await prisma.product.update({ where: { id }, data: { status: ProductStatus.ARCHIVED, archivedAt: new Date() } });
  const updated = await loadProduct(prisma, id);
  announceProduct(updated);
  return toStaffProduct(updated, actor.role);
}

/** Restored products come back as DRAFT so nothing goes live by accident. */
export async function restoreProduct(id: string, actor: Actor) {
  const p = await loadProduct(prisma, id);
  if (p.status !== ProductStatus.ARCHIVED) throw Errors.conflict('Product is not archived');
  await prisma.product.update({ where: { id }, data: { status: ProductStatus.DRAFT, archivedAt: null } });
  return toStaffProduct(await loadProduct(prisma, id), actor.role);
}

/** Permanent delete (ADMIN). Refused when the product has ever been ordered — archive instead. */
export async function deleteProduct(id: string) {
  const p = await loadProduct(prisma, id);
  const variantIds = p.variants.map((v) => v.id);

  const ordered = await prisma.orderItem.count({ where: { variantId: { in: variantIds } } });
  if (ordered > 0) {
    throw Errors.conflict('This product has order history and cannot be deleted. Archive it instead.');
  }
  await prisma.$transaction(async (tx) => {
    await tx.cartItem.deleteMany({ where: { variantId: { in: variantIds } } });
    await tx.stockMovement.deleteMany({ where: { variantId: { in: variantIds } } }); // never sold → ledger is just setup noise
    await tx.product.delete({ where: { id } }); // cascades variants, inventory, images, alerts, reservations, daily stats
  });
  announceProduct({ ...p, status: ProductStatus.ARCHIVED });
}

function announceProduct(p: FullProduct) {
  const payload: ProductUpdatedPayload = {
    productId: p.id,
    basePrice: num(p.basePrice)!,
    salePrice: num(p.salePrice),
    promoTag: p.promoTag,
    status: p.status,
  };
  emitToRoom(SOCKET_ROOMS.product(p.id), SOCKET_EVENTS.PRODUCT_UPDATED, payload);
}

// ───────────────────────── staff: variants ─────────────────────────

export async function addVariants(productId: string, variants: VariantInput[], actor: Actor) {
  const product = await loadProduct(prisma, productId);
  if (product.status === ProductStatus.ARCHIVED) throw Errors.conflict('Restore this product first');

  const existing = new Set(product.variants.map((v) => `${v.color.toLowerCase()}|${v.size.toLowerCase()}`));
  for (const v of variants) {
    if (existing.has(`${v.color.toLowerCase()}|${v.size.toLowerCase()}`)) {
      throw Errors.conflict(`Variant ${v.color} / ${v.size} already exists`);
    }
  }
  try {
    await prisma.$transaction(async (tx) => {
      const skus = await resolveSkus(tx, product.slug, variants);
      const created: { id: string; sku: string }[] = [];
      for (const [i, v] of variants.entries()) {
        created.push(
          await tx.productVariant.create({
            data: {
              productId,
              sku: skus[i]!,
              color: v.color,
              colorHex: v.colorHex,
              size: v.size,
              priceOverride: v.priceOverride,
              inventory: { create: { quantity: v.quantity, lowStockThreshold: v.lowStockThreshold } },
            },
            select: { id: true, sku: true },
          }),
        );
      }
      await recordInitialStock(tx, created, variants, skus, actor.userId);
    });
  } catch (err) {
    throw mapUnique(err);
  }
  return toStaffProduct(await loadProduct(prisma, productId), actor.role);
}

export async function updateVariant(variantId: string, input: UpdateVariantInput, actor: Actor) {
  const v = await prisma.productVariant.findUnique({ where: { id: variantId }, include: { product: true } });
  if (!v) throw Errors.notFound('Variant not found');

  if (input.isActive === false) {
    const others = await prisma.productVariant.count({ where: { productId: v.productId, isActive: true, id: { not: variantId } } });
    if (others === 0 && v.product.status === ProductStatus.ACTIVE) {
      throw Errors.conflict('This is the last active variant of a live product. Archive the product instead.');
    }
  }
  const { lowStockThreshold, ...variantData } = input;
  await prisma.$transaction(async (tx) => {
    if (Object.keys(variantData).length) await tx.productVariant.update({ where: { id: variantId }, data: variantData });
    if (lowStockThreshold !== undefined) await tx.inventory.update({ where: { variantId }, data: { lowStockThreshold } });
  });
  const updated = await loadProduct(prisma, v.productId);
  announceProduct(updated);
  return toStaffProduct(updated, actor.role);
}

// ───────────────────────── staff: images ─────────────────────────

const MAX_IMAGES = 12;

export async function addImage(productId: string, img: ImageInput, actor: Actor) {
  await loadProduct(prisma, productId);
  const count = await prisma.productImage.count({ where: { productId } });
  if (count >= MAX_IMAGES) throw Errors.conflict(`A product can have at most ${MAX_IMAGES} images`);
  await prisma.productImage.create({
    data: { productId, url: img.url, color: img.color, altText: img.altText, sortOrder: count },
  });
  return toStaffProduct(await loadProduct(prisma, productId), actor.role);
}

export async function removeImage(productId: string, imageId: string, actor: Actor) {
  const p = await loadProduct(prisma, productId);
  const img = p.images.find((i) => i.id === imageId);
  if (!img) throw Errors.notFound('Image not found');
  if (p.status === ProductStatus.ACTIVE && p.images.length === 1) {
    throw Errors.conflict('A live product needs at least one image');
  }
  await prisma.$transaction(async (tx) => {
    await tx.productImage.delete({ where: { id: imageId } });
    const rest = p.images.filter((i) => i.id !== imageId);
    for (const [i, r] of rest.entries()) await tx.productImage.update({ where: { id: r.id }, data: { sortOrder: i } });
  });
  return toStaffProduct(await loadProduct(prisma, productId), actor.role);
}

export async function reorderImages(productId: string, imageIds: string[], actor: Actor) {
  const p = await loadProduct(prisma, productId);
  const current = new Set(p.images.map((i) => i.id));
  if (imageIds.length !== current.size || !imageIds.every((id) => current.has(id)) || new Set(imageIds).size !== imageIds.length) {
    throw Errors.badRequest('imageIds must list every image of this product exactly once');
  }
  await prisma.$transaction(imageIds.map((id, i) => prisma.productImage.update({ where: { id }, data: { sortOrder: i } })));
  return toStaffProduct(await loadProduct(prisma, productId), actor.role);
}
