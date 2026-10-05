import { Prisma, prisma } from '@vibethread/database';
import { Errors } from '../lib/errors';
import { uniqueSlug } from '../lib/slug';
import type { CreateCategoryInput, UpdateCategoryInput } from '../schemas/catalog';

interface CategoryNode {
  id: string;
  name: string;
  slug: string;
  parentId: string | null;
  sortOrder: number;
  productCount: number;
  children: CategoryNode[];
}

/** Whole category tree (small table). productCount = ACTIVE products directly in the category. */
export async function getCategoryTree(): Promise<CategoryNode[]> {
  const rows = await prisma.category.findMany({
    orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    include: { _count: { select: { products: { where: { status: 'ACTIVE' } } } } },
  });
  const nodes = new Map<string, CategoryNode>(
    rows.map((r) => [
      r.id,
      {
        id: r.id,
        name: r.name,
        slug: r.slug,
        parentId: r.parentId,
        sortOrder: r.sortOrder,
        productCount: r._count.products,
        children: [],
      },
    ]),
  );
  const roots: CategoryNode[] = [];
  for (const n of nodes.values()) {
    const parent = n.parentId ? nodes.get(n.parentId) : undefined;
    (parent ? parent.children : roots).push(n);
  }
  return roots;
}

export async function getCategoryBySlug(slug: string) {
  const c = await prisma.category.findUnique({ where: { slug } });
  if (!c) throw Errors.notFound('Category not found');
  return c;
}

/** Category id + all descendant ids (for "Tops" to include "T-Shirts"). null if slug unknown. */
export async function categoryIdsWithDescendants(slug: string): Promise<string[] | null> {
  const all = await prisma.category.findMany({ select: { id: true, slug: true, parentId: true } });
  const root = all.find((c) => c.slug === slug);
  if (!root) return null;
  const ids = [root.id];
  for (let i = 0; i < ids.length; i++) {
    for (const c of all) if (c.parentId === ids[i]) ids.push(c.id);
  }
  return ids;
}

export async function createCategory(input: CreateCategoryInput) {
  if (input.parentId) {
    const parent = await prisma.category.findUnique({ where: { id: input.parentId } });
    if (!parent) throw Errors.badRequest('Parent category does not exist');
  }
  const slug = await uniqueSlug(
    async (s) => !!(await prisma.category.findUnique({ where: { slug: s }, select: { id: true } })),
    input.name,
  );
  try {
    return await prisma.category.create({
      data: { name: input.name, slug, parentId: input.parentId ?? null, sortOrder: input.sortOrder ?? 0 },
    });
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      throw Errors.conflict('A category with this name already exists');
    }
    throw err;
  }
}

export async function updateCategory(id: string, input: UpdateCategoryInput) {
  const existing = await prisma.category.findUnique({ where: { id } });
  if (!existing) throw Errors.notFound('Category not found');

  if (input.parentId !== undefined && input.parentId !== null) {
    if (input.parentId === id) throw Errors.badRequest('A category cannot be its own parent');
    const all = await prisma.category.findMany({ select: { id: true, parentId: true } });
    // walk up from the proposed parent; if we meet `id` it would create a cycle
    let cursor: string | null | undefined = input.parentId;
    while (cursor) {
      if (cursor === id) throw Errors.badRequest('That parent would create a loop in the category tree');
      cursor = all.find((c) => c.id === cursor)?.parentId;
    }
    if (!all.some((c) => c.id === input.parentId)) throw Errors.badRequest('Parent category does not exist');
  }
  return prisma.category.update({ where: { id }, data: input });
  // slug is intentionally NOT changed on rename — URLs stay stable.
}

export async function deleteCategory(id: string) {
  const [products, children] = await Promise.all([
    prisma.product.count({ where: { categoryId: id } }),
    prisma.category.count({ where: { parentId: id } }),
  ]);
  if (products > 0) throw Errors.conflict(`Category still has ${products} product(s). Move or archive them first.`);
  if (children > 0) throw Errors.conflict(`Category still has ${children} sub-categor${children === 1 ? 'y' : 'ies'}.`);
  const res = await prisma.category.deleteMany({ where: { id } });
  if (res.count === 0) throw Errors.notFound('Category not found');
}
