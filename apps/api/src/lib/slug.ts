import { randomBytes } from 'node:crypto';

export const slugify = (input: string) =>
  input
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'item';

/** slug, slug-2, slug-3 ... until `exists` says it is free. */
export async function uniqueSlug(exists: (slug: string) => Promise<boolean>, base: string) {
  const root = slugify(base);
  let slug = root;
  let i = 2;
  while (await exists(slug)) {
    slug = i <= 50 ? `${root}-${i}` : `${root}-${randomBytes(3).toString('hex')}`;
    i++;
  }
  return slug;
}
