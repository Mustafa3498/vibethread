import { createHash, randomUUID } from 'node:crypto';
import { Role } from '@vibethread/database';
import jwt, { type JwtPayload, type SignOptions } from 'jsonwebtoken';
import { env } from '../config/env';
import { Errors } from './errors';

export interface AuthContext {
  userId: string;
  role: Role;
  /** access-token expiry, unix seconds */
  exp: number;
}

const ALG = 'HS256' as const;
const ROLE_VALUES = Object.values(Role) as string[];

// ── Access token (short-lived, stateless, sent as Bearer) ──
export function signAccessToken(user: { id: string; role: Role }): string {
  return jwt.sign({ typ: 'access', role: user.role }, env.JWT_ACCESS_SECRET, {
    subject: user.id,
    algorithm: ALG,
    expiresIn: env.JWT_ACCESS_TTL as SignOptions['expiresIn'],
  });
}

export function verifyAccessToken(token: string): AuthContext {
  let payload: JwtPayload;
  try {
    payload = jwt.verify(token, env.JWT_ACCESS_SECRET, { algorithms: [ALG] }) as JwtPayload;
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      throw Errors.unauthorized('Access token expired', 'TOKEN_EXPIRED');
    }
    throw Errors.unauthorized('Invalid access token', 'INVALID_TOKEN');
  }

  if (
    payload.typ !== 'access' ||
    typeof payload.sub !== 'string' ||
    typeof payload.role !== 'string' ||
    !ROLE_VALUES.includes(payload.role) ||
    typeof payload.exp !== 'number'
  ) {
    throw Errors.unauthorized('Invalid access token', 'INVALID_TOKEN');
  }
  return { userId: payload.sub, role: payload.role as Role, exp: payload.exp };
}

// ── Refresh token (long-lived, signed JWT, stored HASHED in DB, rotated on every use) ──
export function signRefreshToken(userId: string): { token: string; expiresAt: Date } {
  const token = jwt.sign({ typ: 'refresh' }, env.JWT_REFRESH_SECRET, {
    subject: userId,
    jwtid: randomUUID(), // guarantees a unique token (and unique hash) per issue
    algorithm: ALG,
    expiresIn: env.JWT_REFRESH_TTL as SignOptions['expiresIn'],
  });
  const { exp } = jwt.decode(token) as JwtPayload;
  return { token, expiresAt: new Date((exp as number) * 1000) };
}

export function verifyRefreshToken(token: string): { userId: string } {
  try {
    const payload = jwt.verify(token, env.JWT_REFRESH_SECRET, {
      algorithms: [ALG],
    }) as JwtPayload;
    if (payload.typ !== 'refresh' || typeof payload.sub !== 'string') throw new Error('bad claims');
    return { userId: payload.sub };
  } catch {
    throw Errors.unauthorized('Invalid or expired refresh token', 'INVALID_REFRESH_TOKEN');
  }
}

export const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');
