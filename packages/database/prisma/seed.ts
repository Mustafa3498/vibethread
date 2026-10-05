import { PrismaClient, Role, StockMovementType } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

// DEV-ONLY credentials. Never reuse in production.
const DEV_PASSWORD = 'Password123!';

async function main() {
  const passwordHash = await bcrypt.hash(DEV_PASSWORD, 10);

  // ── Users (one per role) ──
  const users = [
    { email: 'admin@vibethread.dev', fullName: 'Shop Owner', role: Role.ADMIN },
    { email: 'shopkeeper@vibethread.dev', fullName: 'Shop Keeper', role: Role.SHOPKEEPER },
    { email: 'customer@vibethread.dev', fullName: 'Test Customer', role: Role.CUSTOMER },
  ];
  for (const u of users) {
    await prisma.user.upsert({ where: { email: u.email }, update: {}, create: { ...u, passwordHash } });
  }

  // ── Categories ──
  const tops = await prisma.category.upsert({
    where: { slug: 'tops' },
    update: {},
    create: { name: 'Tops', slug: 'tops', sortOrder: 1 },
  });
  await prisma.category.upsert({ where: { slug: 'bottoms' }, update: {}, create: { name: 'Bottoms', slug: 'bottoms', sortOrder: 2 } });
  await prisma.category.upsert({ where: { slug: 'outerwear' }, update: {}, create: { name: 'Outerwear', slug: 'outerwear', sortOrder: 3 } });

  // ── Sample product with color × size variants ──
  const product = await prisma.product.upsert({
    where: { slug: 'essential-oversized-tee' },
    update: {},
    create: {
      categoryId: tops.id,
      name: 'Essential Oversized Tee',
      slug: 'essential-oversized-tee',
      description: 'Heavyweight cotton oversized tee with a relaxed drop shoulder.',
      fabric: '100% combed cotton, 240 GSM',
      basePrice: 2499,
      costPrice: 900,
      promoTag: 'NEW',
      tags: ['streetwear', 'basics'],
      weatherTags: ['hot', 'mild'],
      status: 'ACTIVE',
    },
  });

  // Images (placeholders — replace with real URLs from the shopkeeper dashboard later)
  const imageCount = await prisma.productImage.count({ where: { productId: product.id } });
  if (imageCount === 0) {
    await prisma.productImage.createMany({
      data: [
        { productId: product.id, color: 'Black', url: 'https://placehold.co/800x1000/111111/ffffff?text=Black+Tee', altText: 'Essential Oversized Tee in Black', sortOrder: 0 },
        { productId: product.id, color: 'Olive', url: 'https://placehold.co/800x1000/5b6340/ffffff?text=Olive+Tee', altText: 'Essential Oversized Tee in Olive', sortOrder: 1 },
      ],
    });
  }

  const colors = [
    { color: 'Black', hex: '#111111', code: 'BLK' },
    { color: 'Olive', hex: '#5b6340', code: 'OLV' },
  ];
  const sizes = ['S', 'M', 'L', 'XL'];

  for (const c of colors) {
    for (const size of sizes) {
      const sku = `VT-TEE-${c.code}-${size}`;
      const variant = await prisma.productVariant.upsert({
        where: { sku },
        update: {},
        create: { productId: product.id, sku, color: c.color, colorHex: c.hex, size },
      });
      const quantity = size === 'M' ? 2 : 20; // M is low on purpose → tests "Only 2 left"
      await prisma.inventory.upsert({
        where: { variantId: variant.id },
        update: {},
        create: { variantId: variant.id, quantity, lowStockThreshold: 5 },
      });
      // ledger: opening stock (once)
      const hasMovement = await prisma.stockMovement.count({ where: { variantId: variant.id } });
      if (hasMovement === 0) {
        await prisma.stockMovement.create({
          data: { variantId: variant.id, type: StockMovementType.RESTOCK, delta: quantity, reason: 'Seed stock' },
        });
      }
    }
  }

  console.log('✅ Seed complete');
  console.log('   admin@vibethread.dev / shopkeeper@vibethread.dev / customer@vibethread.dev');
  console.log(`   dev password: ${DEV_PASSWORD}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
