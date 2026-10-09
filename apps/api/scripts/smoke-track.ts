/**
 * Step B smoke test: guest + signed-in tracking, validation, rollup, staff overview.
 * The API must be running.   cd apps/api && npx tsx scripts/smoke-track.ts
 */
import { randomUUID } from 'node:crypto';

const BASE = process.env.API_URL ?? 'http://localhost:4000';
const PRODUCT_SLUG = process.env.PRODUCT_SLUG ?? 'essential-oversized-tee';
type Json = Record<string, any>;
let failures = 0;

async function api(method: string, path: string, token?: string, body?: unknown) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json: Json = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: res.status, json };
}
function check(name: string, ok: boolean, extra?: unknown) {
  if (ok) console.log(`  ✅ ${name}`);
  else { failures++; console.log(`  ❌ ${name}`, extra === undefined ? '' : JSON.stringify(extra)); }
}
async function login(email: string) {
  const r = await api('POST', '/api/auth/login', undefined, { email, password: 'Password123!' });
  if (r.status !== 200) throw new Error(`login failed for ${email}: ${JSON.stringify(r.json)}`);
  return r.json.accessToken as string;
}

async function main() {
  console.log(`Tracking smoke test against ${BASE}\n`);
  const staff = await login('shopkeeper@vibethread.dev');
  const customer = await login('customer@vibethread.dev');
  const prod = await api('GET', `/api/products/${PRODUCT_SLUG}`);
  const productId = prod.json.product.id as string;

  const sessionId = randomUUID();
  const anonymousId = 'smoke-device-' + randomUUID().slice(0, 8);

  console.log('Ingest');
  const base = { sessionId, anonymousId, deviceType: 'android' };
  let r = await api('POST', '/api/track', undefined, {
    ...base,
    events: [
      { type: 'PAGE_VIEW', page: 'catalog' },
      { type: 'PRODUCT_VIEW', productId, durationMs: 8000, page: 'product' },
      { type: 'PRODUCT_VIEW', productId, durationMs: 4000, page: 'product' },
      { type: 'SIZE_TOGGLE', productId, meta: { toggles: 4 } },
      { type: 'ADD_TO_CART', productId, color: 'Black', size: 'M' },
    ],
  });
  check('guest batch accepted (202, 5)', r.status === 202 && r.json.accepted === 5, r.json);

  r = await api('POST', '/api/track', customer, { ...base, events: [{ type: 'CHECKOUT_START', productId }] });
  check('same session continues when signed in', r.status === 202, r.json);

  r = await api('POST', '/api/track', undefined, { ...base, anonymousId: 'someone-else-device', events: [{ type: 'PAGE_VIEW' }] });
  check('other device cannot reuse the session id (400)', r.status === 400, r.json);

  r = await api('POST', '/api/track', undefined, { ...base, events: [{ type: 'NOT_A_TYPE' }] });
  check('unknown event type rejected (400)', r.status === 400, r.json);

  r = await api('POST', '/api/track', undefined, { ...base, events: [] });
  check('empty batch rejected (400)', r.status === 400, r.json);

  r = await api('POST', '/api/track', undefined, { ...base, events: [{ type: 'PRODUCT_VIEW', productId: randomUUID() }] });
  check('unknown product is kept without productId (202)', r.status === 202, r.json);

  r = await api('POST', '/api/track', undefined, { ...base, events: [{ type: 'SESSION_END', page: 'product' }] });
  check('session end accepted', r.status === 202, r.json);

  console.log('\nStaff analytics');
  r = await api('GET', '/api/manage/analytics/overview', customer);
  check('customer cannot read analytics (403)', r.status === 403, r.json);
  r = await api('GET', '/api/manage/analytics/overview');
  check('guest cannot read analytics (401)', r.status === 401, r.json);

  r = await api('POST', '/api/manage/analytics/rollup', staff);
  check('rollup runs', r.status === 200 && r.json.products >= 1, r.json);

  r = await api('GET', '/api/manage/analytics/overview?days=7', staff);
  const row = (r.json.products as Json[] | undefined)?.find((p) => p.product.id === productId);
  check('overview returns totals', r.status === 200 && r.json.totals?.views >= 2, r.json.totals);
  check('product row: views >= 2', !!row && row.views >= 2, row);
  check('product row: avg dwell > 0', !!row && row.avgDwellMs > 0, row);
  check('product row: cartAdds >= 1, checkouts >= 1, hesitation >= 1', !!row && row.cartAdds >= 1 && row.checkouts >= 1 && row.hesitationHits >= 1, row);
  check('live counters present', typeof r.json.live?.eventsLast30Min === 'number', r.json.live);

  console.log(failures === 0 ? '\nAll good ✅' : `\n${failures} check(s) failed ❌`);
  process.exit(failures === 0 ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
