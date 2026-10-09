/**
 * Step 7 smoke test: cart -> checkout hold -> order -> cancel (stock comes back)
 * and the staff fulfillment pipeline. The API must be running.
 *
 *   cd apps/api && npx tsx scripts/smoke-orders.ts
 */
const BASE = process.env.API_URL ?? 'http://localhost:4000';
const PRODUCT_SLUG = process.env.PRODUCT_SLUG ?? 'essential-oversized-tee';

type Json = Record<string, any>;
let failures = 0;

async function api(method: string, path: string, token?: string, body?: unknown) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json: Json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }
  return { status: res.status, json };
}

function check(name: string, ok: boolean, extra?: unknown) {
  if (ok) console.log(`  ✅ ${name}`);
  else {
    failures++;
    console.log(`  ❌ ${name}`, extra === undefined ? '' : JSON.stringify(extra));
  }
}

async function login(email: string) {
  const r = await api('POST', '/api/auth/login', undefined, { email, password: 'Password123!' });
  if (r.status !== 200) throw new Error(`login failed for ${email}: ${JSON.stringify(r.json)}`);
  return r.json.accessToken as string;
}

async function availableOf(variantId: string): Promise<number> {
  const r = await api('GET', `/api/products/${PRODUCT_SLUG}`);
  const v = (r.json.product.variants as Json[]).find((x) => x.id === variantId);
  return v ? v.available : -1;
}

async function main() {
  console.log(`Smoke test against ${BASE}\n`);

  const customer = await login('customer@vibethread.dev');
  const staff = await login('shopkeeper@vibethread.dev');

  // pick a variant with enough stock
  const prod = await api('GET', `/api/products/${PRODUCT_SLUG}`);
  const variants = (prod.json.product.variants as Json[]).filter((v) => v.available >= 4);
  if (variants.length === 0) throw new Error('No variant with at least 4 units. Restock one (setQuantity 20) and retry.');
  const variant = variants[0]!;
  console.log(`Using variant ${variant.color} / ${variant.size} (available ${variant.available})\n`);

  console.log('Cart');
  let r = await api('DELETE', '/api/cart', customer);
  check('clear cart', r.status === 200 && r.json.cart.itemCount === 0, r.json);

  r = await api('POST', '/api/cart/items', customer, { variantId: variant.id, quantity: 2 });
  check('add 2 -> itemCount 2', r.status === 201 && r.json.cart.itemCount === 2, r.json);

  r = await api('POST', '/api/cart/items', customer, { variantId: variant.id, quantity: 1 });
  check('add 1 more -> itemCount 3', r.json.cart?.itemCount === 3, r.json);

  r = await api('PATCH', `/api/cart/items/${variant.id}`, customer, { quantity: 1 });
  check('set quantity 1', r.json.cart?.itemCount === 1 && r.json.cart.subtotal > 0, r.json);

  r = await api('POST', '/api/cart/items', customer, { variantId: variant.id, quantity: 11 });
  check('quantity 11 rejected (validation)', r.status === 400, r.json);

  r = await api('POST', '/api/cart/items', undefined, { variantId: variant.id, quantity: 1 });
  check('cart needs login', r.status === 401, r.json);

  console.log('\nAddress');
  r = await api('POST', '/api/addresses', customer, {
    label: 'Home',
    line1: 'House 12, Street 4, Block 7',
    city: 'Karachi',
    state: 'Sindh',
    postalCode: '75300',
  });
  check('create address', r.status === 201 && !!r.json.address?.id, r.json);
  const addressId = r.json.address.id as string;

  console.log('\nCheckout hold');
  const before = await availableOf(variant.id);
  r = await api('POST', '/api/checkout', customer);
  check('checkout starts, hold expiry returned', r.status === 200 && !!r.json.checkout?.hold?.expiresAt, r.json);
  const afterHold = await availableOf(variant.id);
  check(`stock held (${before} -> ${afterHold})`, afterHold === before - 1);

  console.log('\nPlace order');
  r = await api('POST', '/api/orders', customer, { addressId, paymentMethod: 'COD', phone: '03001234567' });
  check('order placed (201)', r.status === 201 && !!r.json.order?.orderNumber, r.json);
  const order = r.json.order as Json;
  check('status Placed / UNPAID / COD', order?.statusLabel === 'Placed' && order.paymentStatus === 'UNPAID' && order.paymentMethod === 'COD', order);
  check('estimated delivery set', !!order?.estimatedDelivery);
  const afterOrder = await availableOf(variant.id);
  check(`stock sold (${before} -> ${afterOrder})`, afterOrder === before - 1);

  r = await api('GET', '/api/cart', customer);
  check('new cart is empty', r.json.cart?.itemCount === 0, r.json);

  r = await api('GET', '/api/orders', customer);
  check('order appears in history', (r.json.items as Json[])?.some((o) => o.id === order.id), r.json);

  console.log('\nCancel returns the stock');
  r = await api('POST', `/api/orders/${order.id}/cancel`, customer);
  check('cancelled', r.status === 200 && r.json.order?.status === 'CANCELLED', r.json);
  const afterCancel = await availableOf(variant.id);
  check(`stock back (${afterCancel})`, afterCancel === before);

  r = await api('POST', `/api/orders/${order.id}/cancel`, customer);
  check('cannot cancel twice (409)', r.status === 409, r.json);

  console.log('\nStaff fulfillment');
  await api('POST', '/api/cart/items', customer, { variantId: variant.id, quantity: 1 });
  r = await api('POST', '/api/orders', customer, { addressId, paymentMethod: 'COD' });
  check('second order placed (phone already saved)', r.status === 201, r.json);
  const second = r.json.order as Json;

  r = await api('GET', '/api/manage/orders?status=PENDING_PAYMENT', staff);
  check('staff sees it in the queue', (r.json.items as Json[])?.some((o) => o.id === second.id), r.json);

  const step = async (status: string, extra: Json = {}) =>
    api('PATCH', `/api/manage/orders/${second.id}/status`, staff, { status, ...extra });

  r = await step('DELIVERED');
  check('cannot skip straight to DELIVERED (400)', r.status === 400, r.json);
  r = await step('PACKING');
  check('PACKING', r.json.order?.status === 'PACKING', r.json);
  r = await step('READY_TO_SHIP');
  check('READY_TO_SHIP', r.json.order?.status === 'READY_TO_SHIP', r.json);
  r = await step('SHIPPED', { trackingNumber: 'TCS123456789', courier: 'TCS' });
  check('SHIPPED with tracking', r.json.order?.status === 'SHIPPED' && r.json.order.trackingNumber === 'TCS123456789', r.json);
  r = await api('POST', `/api/orders/${second.id}/cancel`, customer);
  check('customer cannot cancel a shipped order (409)', r.status === 409, r.json);
  r = await step('DELIVERED');
  check('DELIVERED, COD marked PAID', r.json.order?.status === 'DELIVERED' && r.json.order.paymentStatus === 'PAID', r.json);

  r = await api('GET', '/api/manage/orders', customer);
  check('customers cannot open the staff queue (403)', r.status === 403, r.json);

  console.log(failures === 0 ? '\nALL GOOD ✅  (this smoke test used 1 unit of stock for the delivered order)' : `\n${failures} check(s) failed ❌`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('\nSmoke test crashed:', err);
  process.exit(1);
});
