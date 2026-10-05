/**
 * End-to-end smoke test for Step 3 (Auth + RBAC + socket handshake).
 *
 * Requires: docker infra up, DB migrated + seeded, API running (npm run dev).
 * Run:      npm run smoke:auth -w @vibethread/api
 * Extra:    npm run smoke:auth -w @vibethread/api -- --reuse   (also tests stolen-token detection, takes ~11s)
 */
import { io as connect, type Socket } from 'socket.io-client';

const API = process.env.API_URL ?? 'http://localhost:4000';
const DEV_PASSWORD = 'Password123!';
const runReuse = process.argv.includes('--reuse');

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

async function call(method: string, path: string, opts: { token?: string; cookie?: string; body?: unknown } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      ...(opts.body ? { 'Content-Type': 'application/json' } : {}),
      ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
      ...(opts.cookie ? { Cookie: opts.cookie } : {}),
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  const setCookie = res.headers.getSetCookie().find((c) => c.startsWith('vt_refresh='));
  const cookie = setCookie?.split(';')[0]; // "vt_refresh=<token>"
  return { status: res.status, json, cookie, setCookie };
}

function socketConnect(auth: Record<string, unknown>): Promise<{ socket?: Socket; error?: { message: string } }> {
  return new Promise((resolve) => {
    const socket = connect(API, { auth, transports: ['websocket'], reconnection: false });
    socket.on('connect', () => resolve({ socket }));
    socket.on('connect_error', (error) => {
      socket.close();
      resolve({ error });
    });
  });
}
const whoami = (s: Socket) => new Promise<any>((r) => s.emit('whoami', r));

async function main() {
  console.log(`\nVibeThread auth smoke test → ${API}\n`);

  console.log('Login & cookies');
  const admin = await call('POST', '/api/auth/login', {
    body: { email: 'admin@vibethread.dev', password: DEV_PASSWORD },
  });
  check('admin login → 200 + accessToken', admin.status === 200 && !!admin.json?.accessToken, admin.json);
  check('refresh cookie is HttpOnly + scoped to /api/auth', !!admin.setCookie?.includes('HttpOnly') && !!admin.setCookie?.includes('Path=/api/auth'), admin.setCookie);
  check('refresh token NOT leaked in JSON body', !JSON.stringify(admin.json).includes('refresh'));

  const bad = await call('POST', '/api/auth/login', { body: { email: 'admin@vibethread.dev', password: 'Wrong123!' } });
  check('wrong password → 401 INVALID_CREDENTIALS', bad.status === 401 && bad.json?.error?.code === 'INVALID_CREDENTIALS', bad.json);
  const ghost = await call('POST', '/api/auth/login', { body: { email: 'nobody@vibethread.dev', password: 'Wrong123!' } });
  check('unknown email → same 401 (no enumeration)', ghost.status === 401 && ghost.json?.error?.message === bad.json?.error?.message);

  console.log('\nRegister & validation');
  const email = `smoke+${Date.now()}@vibethread.dev`;
  const reg = await call('POST', '/api/auth/register', { body: { email, password: DEV_PASSWORD, fullName: 'Smoke Customer' } });
  check('register → 201, role CUSTOMER', reg.status === 201 && reg.json?.user?.role === 'CUSTOMER', reg.json);
  const dup = await call('POST', '/api/auth/register', { body: { email, password: DEV_PASSWORD, fullName: 'Smoke Customer' } });
  check('duplicate email → 409', dup.status === 409, dup.json);
  const weak = await call('POST', '/api/auth/register', { body: { email: 'x@y.com', password: 'weak', fullName: 'X' } });
  check('weak password → 400 VALIDATION_ERROR', weak.status === 400 && weak.json?.error?.code === 'VALIDATION_ERROR', weak.json);
  const escalate = await call('POST', '/api/auth/register', { body: { email: `esc+${Date.now()}@vibethread.dev`, password: DEV_PASSWORD, fullName: 'Sneaky', role: 'ADMIN' } });
  check('cannot self-register as ADMIN (role ignored)', escalate.status === 201 && escalate.json?.user?.role === 'CUSTOMER', escalate.json);

  console.log('\nRBAC');
  const noToken = await call('GET', '/api/auth/me');
  check('/me without token → 401', noToken.status === 401, noToken.json);
  const garbage = await call('GET', '/api/auth/me', { token: 'not.a.jwt' });
  check('/me with garbage token → 401 INVALID_TOKEN', garbage.status === 401 && garbage.json?.error?.code === 'INVALID_TOKEN', garbage.json);
  const me = await call('GET', '/api/auth/me', { token: reg.json.accessToken });
  check('/me with valid token → own user', me.status === 200 && me.json?.user?.email === email, me.json);
  const custAdmin = await call('GET', '/api/admin/users', { token: reg.json.accessToken });
  check('CUSTOMER → /api/admin/users = 403', custAdmin.status === 403, custAdmin.json);
  const adminList = await call('GET', '/api/admin/users?pageSize=5', { token: admin.json.accessToken });
  check('ADMIN → /api/admin/users = 200', adminList.status === 200 && Array.isArray(adminList.json?.items), adminList.json);
  const staffEmail = `staff+${Date.now()}@vibethread.dev`;
  const staff = await call('POST', '/api/admin/staff', { token: admin.json.accessToken, body: { email: staffEmail, password: DEV_PASSWORD, fullName: 'New Keeper', role: 'SHOPKEEPER' } });
  check('ADMIN creates SHOPKEEPER → 201', staff.status === 201 && staff.json?.user?.role === 'SHOPKEEPER', staff.json);
  const keeper = await call('POST', '/api/auth/login', { body: { email: staffEmail, password: DEV_PASSWORD } });
  const keeperAdmin = await call('GET', '/api/admin/users', { token: keeper.json?.accessToken });
  check('SHOPKEEPER → /api/admin/users = 403', keeperAdmin.status === 403, keeperAdmin.json);

  console.log('\nRefresh rotation');
  const r1 = await call('POST', '/api/auth/refresh', { cookie: admin.cookie });
  check('refresh → 200 + NEW cookie + new accessToken', r1.status === 200 && !!r1.cookie && r1.cookie !== admin.cookie && !!r1.json?.accessToken, r1.json);
  const replay = await call('POST', '/api/auth/refresh', { cookie: admin.cookie });
  check('replaying the OLD refresh token → 401', replay.status === 401, replay.json);
  const noCookie = await call('POST', '/api/auth/refresh');
  check('refresh without cookie → 401 NO_REFRESH_TOKEN', noCookie.status === 401 && noCookie.json?.error?.code === 'NO_REFRESH_TOKEN', noCookie.json);

  if (runReuse) {
    console.log('\nStolen-token detection (waiting 11s past the replay grace window...)');
    await new Promise((r) => setTimeout(r, 11_000));
    const late = await call('POST', '/api/auth/refresh', { cookie: admin.cookie });
    check('late replay → 401 TOKEN_REUSE', late.status === 401 && late.json?.error?.code === 'TOKEN_REUSE', late.json);
    const killed = await call('POST', '/api/auth/refresh', { cookie: r1.cookie });
    check('...and the legit newest token is revoked too (all sessions killed)', killed.status === 401, killed.json);
    // re-login so the remaining steps have a valid admin session
    const again = await call('POST', '/api/auth/login', { body: { email: 'admin@vibethread.dev', password: DEV_PASSWORD } });
    admin.json.accessToken = again.json.accessToken;
    (r1 as any).cookie = again.cookie;
  }

  console.log('\nSocket.io handshake');
  const guest = await socketConnect({ anonymousId: 'smoke-guest-12345678' });
  if (guest.socket) {
    const w = await whoami(guest.socket);
    check('no token → connects as guest in guest:<id> room', w.kind === 'guest' && w.rooms.includes('guest:smoke-guest-12345678'), w);
    guest.socket.close();
  } else check('guest connects', false, guest.error?.message);

  const bogus = await socketConnect({ token: 'not.a.jwt' });
  check('garbage token → connect_error INVALID_TOKEN', bogus.error?.message === 'INVALID_TOKEN', bogus.error?.message);

  const cust = await socketConnect({ token: reg.json.accessToken });
  if (cust.socket) {
    const w = await whoami(cust.socket);
    check('CUSTOMER socket: in user room, NOT in staff/admin', w.role === 'CUSTOMER' && !w.rooms.includes('staff') && !w.rooms.includes('admin'), w);
    cust.socket.close();
  } else check('customer socket connects', false, cust.error?.message);

  const keep = await socketConnect({ token: keeper.json.accessToken });
  if (keep.socket) {
    const w = await whoami(keep.socket);
    check('SHOPKEEPER socket: in staff room, NOT admin', w.rooms.includes('staff') && !w.rooms.includes('admin'), w);
    keep.socket.close();
  } else check('shopkeeper socket connects', false, keep.error?.message);

  const adm = await socketConnect({ token: admin.json.accessToken });
  if (adm.socket) {
    const w = await whoami(adm.socket);
    check('ADMIN socket: in staff + admin rooms', w.rooms.includes('staff') && w.rooms.includes('admin'), w);
    adm.socket.close();
  } else check('admin socket connects', false, adm.error?.message);

  // guest → logs in later → upgrades the same socket via auth:renew (no reconnect)
  const up = await socketConnect({});
  if (up.socket) {
    const ack = await new Promise<any>((r) => up.socket!.emit('auth:renew', admin.json.accessToken, r));
    const w = await whoami(up.socket);
    check('guest socket upgrades via auth:renew → ADMIN rooms, guest room dropped', ack.ok && w.role === 'ADMIN' && w.rooms.includes('admin') && !w.rooms.some((r: string) => r.startsWith('guest:')), { ack, w });
    const wrong = await new Promise<any>((r) => up.socket!.emit('auth:renew', reg.json.accessToken, r));
    check('renew with a DIFFERENT user\'s token → rejected', wrong.ok === false, wrong);
    up.socket.close();
  } else check('upgrade socket connects', false, up.error?.message);

  console.log('\nLogout');
  const lo = await call('POST', '/api/auth/logout', { cookie: r1.cookie });
  check('logout → 204', lo.status === 204, lo.json);
  const after = await call('POST', '/api/auth/refresh', { cookie: r1.cookie });
  check('refresh after logout → 401', after.status === 401, after.json);

  console.log(`\n${failed === 0 ? '🎉 ALL PASSED' : '💥 FAILURES'}  —  ${passed} passed, ${failed} failed\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('Smoke test crashed (is the API running?):', e);
  process.exit(1);
});
