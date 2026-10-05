import type { NextFunction, Request, Response } from 'express';
import type { Role } from '@vibethread/database';
import { Errors } from '../lib/errors';
import { type AuthContext, verifyAccessToken } from '../lib/tokens';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

function bearer(req: Request): string | undefined {
  const header = req.headers.authorization;
  if (!header) return undefined;
  const [scheme, token] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' && token ? token : undefined;
}

/** Requires a valid access token. Sets req.auth. */
export function authenticate(req: Request, _res: Response, next: NextFunction) {
  const token = bearer(req);
  if (!token) return next(Errors.unauthorized());
  try {
    req.auth = verifyAccessToken(token);
    next();
  } catch (err) {
    next(err);
  }
}

/** Guests allowed (carts, tracking). If a token IS sent it must be valid. */
export function optionalAuth(req: Request, _res: Response, next: NextFunction) {
  const token = bearer(req);
  if (!token) return next();
  try {
    req.auth = verifyAccessToken(token);
    next();
  } catch (err) {
    next(err);
  }
}

/** Use AFTER authenticate. requireRole('ADMIN') or requireRole('SHOPKEEPER', 'ADMIN'). */
export const requireRole =
  (...allowed: Role[]) =>
  (req: Request, _res: Response, next: NextFunction) => {
    if (!req.auth) return next(Errors.unauthorized());
    if (!allowed.includes(req.auth.role)) return next(Errors.forbidden());
    next();
  };
