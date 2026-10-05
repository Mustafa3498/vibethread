/**
 * Inventory ENGINE test — calls the service layer directly (reservations are internal until Step 7).
 * Needs: infra up, Step 4 migration applied, DB seeded. API does NOT need to be running.
 * Run:   npm run smoke:inventory -w @vibethread/api
 */
import '../src/config/env'; // loads root .env
import { prisma } from '@vibethread/database';
import {
  adjustStock,
  commitReservations,
  expireStaleReservations,
  releaseReservations,
  reserveStock,
  returnStock,
} from '../src/services/inventory.service';

let passed = 0;
let failed = 0;
function check(name: string, ok: boolean, extra?: unknown) {
  if (ok) {
    passed++;
    console.log(`  ✅ ${name}`);
  } else {
    failed++;
    console.log(`  ❌ ${name}`, extra !== undefined ? JSON.stringify(extra) : '');
  }
}
const stock = async (variantId: string) => {
  const i = await prisma.inventory.findUniqueOrThrow({ where: { variantId } });
  return { quantity: i.quantity, reserved: i.reserved, available: i.quantity - i.reserved };
};

async function main() {
  console.log('\nVibeThread inventory engine test\n');
  const tag = Date.now().toString(36);

  // Isolated fixture: own category/product/variant, cleaned up at the end.
  const category = await prisma.category.create({ data: { name: `Engine Test ${tag}`, slug: `engine-test-${tag}` } });
  const product = await prisma.product.create({
    data: {
      categoryId: category.id, name: `Engine Tee ${tag}`, slug: `engine-tee-${tag}`, description: 'x', basePrice: 100, status: 'DRAFT',
      variants: { create: [{ sku: `ENG-${tag}-A`, color: 'Black', size: 'M', inventory: { create: { quantity: 10, lowStockThreshold: 2 } } }] },
    },
    include: { variants: true },
  });
  const v = product.variants[0]!.id;
  const cartA = `cart-a-${tag}`;
  const cartB = `cart-b-${tag}`;

  try {
    console.log('Reserve / release');
    await reserveStock({ cartId: cartA, items: [{ variantId: v, quantity: 4 }] });
    let s = await stock(v);
    check('reserve 4 → reserved 4, available 6', s.reserved === 4 && s.available === 6, s);

    await reserveStock({ cartId: cartB, items: [{ variantId: v, quantity: 6 }] });
    s = await stock(v);
    check('second cart takes the rest → available 0', s.available === 0, s);

    let err: any;
    await reserveStock({ cartId: `cart-c-${tag}`, items: [{ variantId: v, quantity: 1 }] }).catch((e) => (err = e));
    check('overselling blocked → 409 INSUFFICIENT_STOCK', err?.status === 409 && err?.code === 'INSUFFICIENT_STOCK' && err?.details?.available === 0, err);

    const released = await releaseReservations({ cartId: cartB });
    s = await stock(v);
    check('release cart B → 1 hold freed, available 6', released === 1 && s.available === 6, { released, s });
    check('releasing twice is a no-op', (await releaseReservations({ cartId: cartB })) === 0);

    console.log('\nAtomic multi-line reservation');
    const v2 = await prisma.productVariant.create({
      data: { productId: product.id, sku: `ENG-${tag}-B`, color: 'Black', size: 'L', inventory: { create: { quantity: 1 } } },
    });
    err = undefined;
    await reserveStock({ cartId: `cart-d-${tag}`, items: [{ variantId: v, quantity: 2 }, { variantId: v2.id, quantity: 5 }] }).catch((e) => (err = e));
    s = await stock(v);
    check('one line fails → whole reservation rolls back (v untouched)', err?.code === 'INSUFFICIENT_STOCK' && s.reserved === 4, { err: err?.code, s });

    console.log('\nCommit (sale)');
    const committed = await commitReservations({ cartId: cartA, orderId: `order-${tag}` });
    s = await stock(v);
    check('commit → quantity 6, reserved 0', committed === 1 && s.quantity === 6 && s.reserved === 0, { committed, s });
    const sale = await prisma.stockMovement.findFirst({ where: { variantId: v, type: 'SALE' } });
    check('SALE movement written with delta -4', sale?.delta === -4, sale);

    console.log('\nExpiry');
    await reserveStock({ cartId: `cart-e-${tag}`, items: [{ variantId: v, quantity: 3 }], ttlMinutes: 15 });
    await prisma.stockReservation.updateMany({ where: { cartId: `cart-e-${tag}` }, data: { expiresAt: new Date(Date.now() - 1000) } });
    const expired = await expireStaleReservations();
    s = await stock(v);
    check('expired hold released by job logic → reserved 0', expired >= 1 && s.reserved === 0, { expired, s });
    const res = await prisma.stockReservation.findFirst({ where: { cartId: `cart-e-${tag}` } });
    check('reservation marked EXPIRED', res?.status === 'EXPIRED', res);

    console.log('\nManual adjustments vs holds');
    await reserveStock({ cartId: `cart-f-${tag}`, items: [{ variantId: v, quantity: 5 }] });
    err = undefined;
    await adjustStock(v, { setQuantity: 3 }, null).catch((e) => (err = e));
    check('cannot set stock below active holds → 409', err?.status === 409, err);
    await releaseReservations({ cartId: `cart-f-${tag}` });
    const adj = await adjustStock(v, { setQuantity: 3, reason: 'engine test' }, null);
    check('after release, setQuantity 3 works', adj.quantity === 3 && adj.delta === -3, adj);

    console.log('\nConcurrency (the oversell test)');
    await adjustStock(v, { setQuantity: 5 }, null);
    const attempts = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) => reserveStock({ cartId: `race-${tag}-${i}`, items: [{ variantId: v, quantity: 1 }] })),
    );
    const ok = attempts.filter((a) => a.status === 'fulfilled').length;
    s = await stock(v);
    check('20 simultaneous buyers, 5 units → exactly 5 succeed', ok === 5 && s.reserved === 5 && s.available === 0, { ok, s });
    for (let i = 0; i < 20; i++) await releaseReservations({ cartId: `race-${tag}-${i}` });

    console.log('\nReturns & DB safety net');
    await returnStock({ variantId: v, quantity: 2, orderId: `order-${tag}` });
    s = await stock(v);
    check('return +2 → quantity 7', s.quantity === 7, s);
    err = undefined;
    await prisma.$executeRaw`UPDATE "Inventory" SET reserved = quantity + 1 WHERE "variantId" = ${v}`.catch((e) => (err = e));
    check('DB CHECK constraint rejects reserved > quantity', !!err, 'constraint missing — did you paste inventory_constraints.sql into the migration?');

    const ledger = await prisma.stockMovement.groupBy({ by: ['type'], where: { variantId: v }, _count: true });
    console.log('  ℹ️  ledger rows by type:', Object.fromEntries(ledger.map((l) => [l.type, l._count])));
  } finally {
    // cleanup fixture
    const variantIds = (await prisma.productVariant.findMany({ where: { productId: product.id }, select: { id: true } })).map((x) => x.id);
    await prisma.stockMovement.deleteMany({ where: { variantId: { in: variantIds } } });
    await prisma.product.delete({ where: { id: product.id } });
    await prisma.category.delete({ where: { id: category.id } });
    await prisma.$disconnect();
  }

  console.log(`\n${failed === 0 ? '🎉 ALL PASSED' : '💥 FAILURES'}  —  ${passed} passed, ${failed} failed\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error('Inventory test crashed:', e);
  await prisma.$disconnect();
  process.exit(1);
});
