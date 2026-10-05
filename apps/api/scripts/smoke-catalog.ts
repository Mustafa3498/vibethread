/**
 * Smoke test for Step 4 over HTTP + Socket.io: categories, products, RBAC, stock, live updates.
 *
 * Requires: infra up, Step 4 migration applied, DB seeded, API running (npm run dev).
 * Run:      npm run smoke:catalog -w @vibethread/api
 */
import { io as connect, type Socket } from 'socket.io-client';

const API = process.env.API_URL ?? 'http://localhost:4000';
const PW = 'Password123!';
let passed = 0;
let failed = 0;

function check(name: string, ok: boolean, extra?: unknown) {
  if (ok) {
    passed++;
    console.log(`  ✅ ${name}`);
  } else {
    failed++;
    console.log(`  ❌ ${name}`, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : '');
  }
}

async function call(method: string, path: string, opts: { token?: string; body?: unknown } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      ...(opts.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
    },
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null };
}
async function login(email: string) {
  const r = await call('POST', '/api/auth/login', { body: { email, password: PW } });
  if (!r.json?.accessToken) throw new Error(`login failed for ${email}: ${JSON.stringify(r.json)}`);
  return r.json.accessToken as string;
}
function connectSocket(auth: Record<string, unknown>): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const s = connect(API, { auth, transports: ['websocket'], reconnection: false });
    s.on('connect', () => resolve(s));
    s.on('connect_error', reject);
  });
}
const waitFor = <T>(s: Socket, event: string, ms = 3000, pred: (p: T) => boolean = () => true) =>
  new Promise<T | null>((resolve) => {
    const t = setTimeout(() => resolve(null), ms);
    s.on(event, (p: T) => {
      if (pred(p)) {
        clearTimeout(t);
        resolve(p);
      }
    });
  });

async function main() {
  console.log(`\nVibeThread catalog + inventory smoke test → ${API}\n`);
  const admin = await login('admin@vibethread.dev');
  const keeper = await login('shopkeeper@vibethread.dev');
  const customer = await login('customer@vibethread.dev');
  const tag = Date.now().toString(36);

  console.log('Categories');
  const pub = await call('GET', '/api/categories');
  check('public category tree → 200', pub.status === 200 && Array.isArray(pub.json?.items), pub.json);
  const noAuthCat = await call('POST', '/api/manage/categories', { body: { name: 'Nope' } });
  check('create category without token → 401', noAuthCat.status === 401);
  const custCat = await call('POST', '/api/manage/categories', { token: customer, body: { name: 'Nope' } });
  check('CUSTOMER create category → 403', custCat.status === 403);
  const cat = await call('POST', '/api/manage/categories', { token: keeper, body: { name: `Smoke Hoodies ${tag}` } });
  check('SHOPKEEPER creates category → 201 + slug', cat.status === 201 && !!cat.json?.category?.slug, cat.json);
  const child = await call('POST', '/api/manage/categories', { token: keeper, body: { name: `Zip Hoodies ${tag}`, parentId: cat.json.category.id } });
  check('sub-category created', child.status === 201, child.json);
  const loop = await call('PATCH', `/api/manage/categories/${cat.json.category.id}`, { token: keeper, body: { parentId: child.json.category.id } });
  check('category loop prevented → 400', loop.status === 400, loop.json);

  console.log('\nProduct creation & validation');
  const body = {
    categoryId: child.json.category.id,
    name: `Smoke Hoodie ${tag}`,
    description: 'Test hoodie',
    basePrice: 5999,
    tags: ['Streetwear', 'smoke'],
    weatherTags: ['cold'],
    variants: [
      { color: 'olive', size: 'm', quantity: 12 },
      { color: 'Black', size: 'm', quantity: 8, lowStockThreshold: 5 },
      { color: 'Black', size: 'l', quantity: 6 },
    ],
  };
  const dup = await call('POST', '/api/manage/products', { token: keeper, body: { ...body, variants: [{ color: 'Black', size: 'M' }, { color: 'black', size: 'm' }] } });
  check('duplicate color+size in payload → 400', dup.status === 400, dup.json);
  const badSale = await call('POST', '/api/manage/products', { token: keeper, body: { ...body, salePrice: 7000 } });
  check('salePrice >= basePrice → 400', badSale.status === 400, badSale.json);
  const keeperCost = await call('POST', '/api/manage/products', { token: keeper, body: { ...body, costPrice: 2000 } });
  check('SHOPKEEPER setting costPrice → 403', keeperCost.status === 403, keeperCost.json);
  const noImgActive = await call('POST', '/api/manage/products', { token: keeper, body: { ...body, status: 'ACTIVE' } });
  check('publish without image → 400', noImgActive.status === 400, noImgActive.json);

  const created = await call('POST', '/api/manage/products', { token: keeper, body });
  const p = created.json?.product;
  check('create product (DRAFT) → 201', created.status === 201 && p?.status === 'DRAFT', created.json);
  check('colors normalised to Title Case', p?.variants.every((v: any) => v.color === 'Olive' || v.color === 'Black'), p?.variants);
  check('SKUs auto-generated + unique', new Set(p?.variants.map((v: any) => v.sku)).size === 3 && p.variants.every((v: any) => /^[A-Z0-9-]+$/.test(v.sku)), p?.variants.map((v: any) => v.sku));
  check('shopkeeper response hides costPrice', !('costPrice' in (p ?? {})));
  check('initial stock reflected', p?.totalAvailable === 26, p?.totalAvailable);
  const hidden = await call('GET', `/api/products/${p.slug}`);
  check('DRAFT product invisible to public → 404', hidden.status === 404);

  console.log('\nPublishing, images, public catalog');
  const pubNoImg = await call('PATCH', `/api/manage/products/${p.id}`, { token: keeper, body: { status: 'ACTIVE' } });
  check('PATCH status ACTIVE without image → 400', pubNoImg.status === 400, pubNoImg.json);
  const img1 = await call('POST', `/api/manage/products/${p.id}/images`, { token: keeper, body: { url: 'https://placehold.co/800x1000/111/fff?text=Hoodie', color: 'Black' } });
  check('add image → 201', img1.status === 201 && img1.json.product.images.length === 1, img1.json);
  const httpImg = await call('POST', `/api/manage/products/${p.id}/images`, { token: keeper, body: { url: 'http://insecure.example/x.jpg' } });
  check('non-https image URL → 400', httpImg.status === 400);
  const live = await call('PATCH', `/api/manage/products/${p.id}`, { token: keeper, body: { status: 'ACTIVE', promoTag: 'NEW', salePrice: 4999 } });
  check('publish + sale price → ACTIVE', live.status === 200 && live.json.product.status === 'ACTIVE', live.json);

  const detail = await call('GET', `/api/products/${p.slug}`);
  check('public detail → 200', detail.status === 200, detail.json);
  check('public detail: no costPrice, no raw quantities', !('costPrice' in detail.json.product) && !('quantity' in detail.json.product.variants[0]), detail.json.product?.variants?.[0]);
  check('variant price = salePrice', detail.json.product.variants[0].price === 4999);
  const list = await call('GET', `/api/products?category=${cat.json.category.slug}&sort=price_asc`);
  check('listing by PARENT category includes child-category product', list.status === 200 && list.json.items.some((i: any) => i.id === p.id), list.json);
  const color = await call('GET', `/api/products?category=${cat.json.category.slug}&color=olive&size=M`);
  check('filter color(case-insens)+size', color.json.items.some((i: any) => i.id === p.id));
  const wrongSize = await call('GET', `/api/products?category=${cat.json.category.slug}&size=XL`);
  check('filter size XL → no match', wrongSize.json.items.length === 0);
  const weather = await call('GET', `/api/products?category=${cat.json.category.slug}&weather=cold&inStock=true`);
  check('filter weather=cold + inStock', weather.json.items.some((i: any) => i.id === p.id), weather.json);
  const search = await call('GET', `/api/products?q=smoke%20hoodie%20${tag}`);
  check('text search', search.json.items.some((i: any) => i.id === p.id), search.json);

  console.log('\nRBAC on cost price');
  const adminCost = await call('PATCH', `/api/manage/products/${p.id}`, { token: admin, body: { costPrice: 2100 } });
  check('ADMIN sets costPrice', adminCost.status === 200 && adminCost.json.product.costPrice === 2100, adminCost.json);
  const keeperView = await call('GET', `/api/manage/products/${p.id}`, { token: keeper });
  check('SHOPKEEPER view still hides costPrice', !('costPrice' in keeperView.json.product));
  const keeperDel = await call('DELETE', `/api/manage/products/${p.id}`, { token: keeper });
  check('SHOPKEEPER hard delete → 403', keeperDel.status === 403);

  console.log('\nStock adjustments + live updates');
  const blackM = detail.json.product.variants.find((v: any) => v.color === 'Black' && v.size === 'M');
  const guest = await connectSocket({ anonymousId: `smoke-${tag}-guestsock` });
  const staffSock = await connectSocket({ token: keeper });
  const watch = await new Promise<any>((r) => guest.emit('product:watch', p.id, r));
  check('guest can watch a product room', watch?.ok === true, watch);

  const stockEv = waitFor<any>(guest, 'stock:updated', 3000, (e) => e.variantId === blackM.id);
  const staffEv = waitFor<any>(staffSock, 'stock:updated', 3000, (e) => e.variantId === blackM.id);
  const restock = await call('PATCH', `/api/manage/inventory/${blackM.id}`, { token: keeper, body: { delta: 4, reason: 'Smoke restock' } });
  check('restock +4 → quantity 12', restock.status === 200 && restock.json.stock.quantity === 12, restock.json);
  const ge = await stockEv;
  const se = await staffEv;
  check('guest receives live stock:updated (available=12, no quantity leak)', ge?.available === 12 && !('quantity' in (ge ?? {})), ge);
  check('staff receives stock:updated with quantity/reserved', se?.quantity === 12 && se?.reserved === 0, se);

  const alertEv = waitFor<any>(staffSock, 'inventory:alert', 3000, (a) => a.variantId === blackM.id);
  const low = await call('PATCH', `/api/manage/inventory/${blackM.id}`, { token: keeper, body: { setQuantity: 3, reason: 'Smoke count' } });
  check('setQuantity 3 → delta -9', low.status === 200 && low.json.stock.delta === -9, low.json);
  const alert = await alertEv;
  check('staff receives LOW_STOCK alert', alert?.type === 'LOW_STOCK', alert);
  const pubLow = await call('GET', `/api/products/${p.slug}`);
  check('public variant now lowStock=true, available=3', pubLow.json.product.variants.find((v: any) => v.id === blackM.id)?.lowStock === true);

  const zero = await call('PATCH', `/api/manage/inventory/${blackM.id}`, { token: keeper, body: { setQuantity: 0 } });
  const alerts = await call('GET', '/api/manage/alerts?unread=true', { token: keeper });
  const mine = alerts.json.items.filter((a: any) => a.variantId === blackM.id);
  check('out of stock → OUT_OF_STOCK open, LOW_STOCK auto-resolved', zero.status === 200 && mine.some((a: any) => a.type === 'OUT_OF_STOCK') && !mine.some((a: any) => a.type === 'LOW_STOCK'), mine);
  const neg = await call('PATCH', `/api/manage/inventory/${blackM.id}`, { token: keeper, body: { delta: -5 } });
  check('going below 0 → 400', neg.status === 400, neg.json);
  const both = await call('PATCH', `/api/manage/inventory/${blackM.id}`, { token: keeper, body: { delta: 1, setQuantity: 5 } });
  check('delta + setQuantity together → 400', both.status === 400);
  await call('PATCH', `/api/manage/inventory/${blackM.id}`, { token: keeper, body: { setQuantity: 8 } });
  const recovered = await call('GET', '/api/manage/alerts?unread=true', { token: keeper });
  check('restock auto-resolves OUT_OF_STOCK alert', !recovered.json.items.some((a: any) => a.variantId === blackM.id && a.type === 'OUT_OF_STOCK'));

  const moves = await call('GET', `/api/manage/inventory-movements?variantId=${blackM.id}`, { token: keeper });
  check('ledger has initial + 4 adjustments (newest first)', moves.status === 200 && moves.json.total >= 5 && moves.json.items[0].delta === 8, moves.json.items?.map((m: any) => m.delta));
  const inv = await call('GET', `/api/manage/inventory?q=${tag}`, { token: keeper });
  check('inventory list searchable', inv.status === 200 && inv.json.total === 3, inv.json.total);
  const lowList = await call('GET', '/api/manage/inventory?lowStock=true', { token: keeper });
  check('inventory lowStock filter works (seed has size-M tee at 2)', lowList.status === 200 && lowList.json.items.every((i: any) => i.status === 'LOW_STOCK'), lowList.json);

  console.log('\nArchive / restore / delete');
  const priceEv = waitFor<any>(guest, 'product:updated', 3000, (e) => e.productId === p.id);
  const arch = await call('POST', `/api/manage/products/${p.id}/archive`, { token: keeper });
  check('archive → ARCHIVED', arch.status === 200 && arch.json.product.status === 'ARCHIVED', arch.json);
  const pe = await priceEv;
  check('watchers get product:updated (status ARCHIVED)', pe?.status === 'ARCHIVED', pe);
  const gone = await call('GET', `/api/products/${p.slug}`);
  check('archived product hidden from public', gone.status === 404);
  const statusArch = await call('PATCH', `/api/manage/products/${p.id}`, { token: keeper, body: { status: 'ACTIVE' } });
  check('cannot publish while archived → 409', statusArch.status === 409);
  const rest = await call('POST', `/api/manage/products/${p.id}/restore`, { token: keeper });
  check('restore → DRAFT', rest.status === 200 && rest.json.product.status === 'DRAFT');
  const catBusy = await call('DELETE', `/api/manage/categories/${child.json.category.id}`, { token: keeper });
  check('delete category with products → 409', catBusy.status === 409, catBusy.json);
  const del = await call('DELETE', `/api/manage/products/${p.id}`, { token: admin });
  check('ADMIN hard-deletes never-sold product → 204', del.status === 204, del.json);
  const after = await call('GET', `/api/manage/products/${p.id}`, { token: admin });
  check('deleted product → 404', after.status === 404);
  const delChild = await call('DELETE', `/api/manage/categories/${child.json.category.id}`, { token: keeper });
  const delParent = await call('DELETE', `/api/manage/categories/${cat.json.category.id}`, { token: keeper });
  check('empty categories can be deleted (child, then parent)', delChild.status === 204 && delParent.status === 204, [delChild.json, delParent.json]);

  guest.close();
  staffSock.close();
  console.log(`\n${failed === 0 ? '🎉 ALL PASSED' : '💥 FAILURES'}  —  ${passed} passed, ${failed} failed\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('Smoke test crashed (is the API running and the Step 4 migration applied?):', e);
  process.exit(1);
});
