import { Prisma, prisma, Role } from '@vibethread/database';
import type { AuthUser } from '@vibethread/shared';
import { Errors } from '../lib/errors';
import { hashPassword, verifyPassword } from '../lib/password';
import {
  hashToken,
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../lib/tokens';

// If a rotated token is replayed within this window we assume a multi-tab race,
// not theft: reject the request but don't nuke the user's other sessions.
const REUSE_GRACE_MS = 10_000;

const userSelect = {
  id: true,
  email: true,
  fullName: true,
  phone: true,
  role: true,
  isActive: true,
  createdAt: true,
} satisfies Prisma.UserSelect;

type DbUser = Prisma.UserGetPayload<{ select: typeof userSelect }>;

export const toAuthUser = (u: DbUser): AuthUser => ({
  id: u.id,
  email: u.email,
  fullName: u.fullName,
  phone: u.phone,
  role: u.role,
  isActive: u.isActive,
  createdAt: u.createdAt.toISOString(),
});

export interface Session {
  user: AuthUser;
  accessToken: string;
  refreshToken: string;
  refreshExpiresAt: Date;
}

async function issueSession(user: DbUser): Promise<Session> {
  const accessToken = signAccessToken(user);
  const { token: refreshToken, expiresAt } = signRefreshToken(user.id);
  await prisma.refreshToken.create({
    data: { userId: user.id, tokenHash: hashToken(refreshToken), expiresAt },
  });
  return { user: toAuthUser(user), accessToken, refreshToken, refreshExpiresAt: expiresAt };
}

export const revokeAllForUser = (userId: string) =>
  prisma.refreshToken.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });

// ───────────── Register / Login ─────────────

export async function register(input: {
  email: string;
  password: string;
  fullName: string;
  phone?: string;
}): Promise<Session> {
  const existing = await prisma.user.findUnique({ where: { email: input.email } });
  if (existing) throw Errors.conflict('An account with this email already exists');

  try {
    const user = await prisma.user.create({
      data: {
        email: input.email,
        passwordHash: await hashPassword(input.password),
        fullName: input.fullName,
        phone: input.phone,
        role: Role.CUSTOMER, // public signup is ALWAYS a customer
      },
      select: userSelect,
    });
    return issueSession(user);
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      throw Errors.conflict('An account with this email already exists');
    }
    throw err;
  }
}

export async function login(email: string, password: string): Promise<Session> {
  const user = await prisma.user.findUnique({
    where: { email },
    select: { ...userSelect, passwordHash: true },
  });

  const ok = await verifyPassword(password, user?.passwordHash);
  if (!user || !ok || !user.isActive) {
    // Same message for every failure → no account enumeration.
    throw Errors.unauthorized('Invalid email or password', 'INVALID_CREDENTIALS');
  }
  const { passwordHash: _omit, ...safeUser } = user;
  return issueSession(safeUser);
}

// ───────────── Refresh rotation ─────────────

export async function rotateSession(refreshToken: string): Promise<Session> {
  verifyRefreshToken(refreshToken); // cheap signature/expiry check before touching the DB

  const row = await prisma.refreshToken.findUnique({
    where: { tokenHash: hashToken(refreshToken) },
    include: { user: { select: { ...userSelect } } },
  });
  if (!row) throw Errors.unauthorized('Invalid refresh token', 'INVALID_REFRESH_TOKEN');

  if (row.revokedAt) return handleReplay(row.userId, row.revokedAt);
  if (row.expiresAt <= new Date()) {
    throw Errors.unauthorized('Refresh token expired', 'INVALID_REFRESH_TOKEN');
  }
  if (!row.user.isActive) throw Errors.unauthorized('Account disabled', 'ACCOUNT_DISABLED');

  // Atomic claim: only ONE concurrent request can flip revokedAt from null.
  const claimed = await prisma.refreshToken.updateMany({
    where: { id: row.id, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  if (claimed.count === 0) return handleReplay(row.userId, new Date());

  return issueSession(row.user);
}

async function handleReplay(userId: string, revokedAt: Date): Promise<never> {
  if (Date.now() - revokedAt.getTime() > REUSE_GRACE_MS) {
    // A token that was already rotated came back late → likely stolen. Kill every session.
    await revokeAllForUser(userId);
    throw Errors.unauthorized('Refresh token reuse detected. Please log in again.', 'TOKEN_REUSE');
  }
  throw Errors.unauthorized('Refresh token already used', 'INVALID_REFRESH_TOKEN');
}

// ───────────── Logout ─────────────

export async function logout(refreshToken: string | undefined) {
  if (!refreshToken) return;
  await prisma.refreshToken.updateMany({
    where: { tokenHash: hashToken(refreshToken), revokedAt: null },
    data: { revokedAt: new Date() },
  });
}

// ───────────── Users / staff (admin) ─────────────

export async function getUserById(id: string): Promise<AuthUser> {
  const user = await prisma.user.findUnique({ where: { id }, select: userSelect });
  if (!user) throw Errors.notFound('User not found');
  return toAuthUser(user);
}

export async function createStaff(input: {
  email: string;
  password: string;
  fullName: string;
  phone?: string;
  role: 'SHOPKEEPER' | 'ADMIN';
}): Promise<AuthUser> {
  try {
    const user = await prisma.user.create({
      data: {
        email: input.email,
        passwordHash: await hashPassword(input.password),
        fullName: input.fullName,
        phone: input.phone,
        role: input.role,
      },
      select: userSelect,
    });
    return toAuthUser(user);
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      throw Errors.conflict('An account with this email already exists');
    }
    throw err;
  }
}

export async function listUsers(opts: { role?: Role; page: number; pageSize: number }) {
  const where = opts.role ? { role: opts.role } : {};
  const [total, rows] = await Promise.all([
    prisma.user.count({ where }),
    prisma.user.findMany({
      where,
      select: userSelect,
      orderBy: { createdAt: 'desc' },
      skip: (opts.page - 1) * opts.pageSize,
      take: opts.pageSize,
    }),
  ]);
  return { total, page: opts.page, pageSize: opts.pageSize, items: rows.map(toAuthUser) };
}

export async function setUserActive(id: string, isActive: boolean): Promise<AuthUser> {
  const exists = await prisma.user.findUnique({ where: { id }, select: { id: true } });
  if (!exists) throw Errors.notFound('User not found');

  const user = await prisma.user.update({ where: { id }, data: { isActive }, select: userSelect });
  if (!isActive) await revokeAllForUser(id); // kicks them out at next refresh (≤ access TTL)
  return toAuthUser(user);
}
