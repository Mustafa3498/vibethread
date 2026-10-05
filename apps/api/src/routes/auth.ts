import { Router, type Response } from 'express';
import { z } from 'zod';
import { env } from '../config/env';
import { asyncHandler } from '../lib/async-handler';
import { authenticate } from '../middleware/auth';
import { authRateLimiter } from '../middleware/rate-limit';
import { validate } from '../middleware/validate';
import * as auth from '../services/auth.service';

export const authRouter = Router();

export const REFRESH_COOKIE = 'vt_refresh';

// Cookie is only sent to /api/auth/* (refresh + logout), never to normal API calls.
function setRefreshCookie(res: Response, token: string, expires: Date) {
  res.cookie(REFRESH_COOKIE, token, {
    httpOnly: true,
    secure: env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/api/auth',
    expires,
  });
}
const clearRefreshCookie = (res: Response) =>
  res.clearCookie(REFRESH_COOKIE, { path: '/api/auth' });

function sendSession(res: Response, status: number, s: auth.Session) {
  setRefreshCookie(res, s.refreshToken, s.refreshExpiresAt);
  res.status(status).json({ user: s.user, accessToken: s.accessToken });
}

// ── schemas ──
const email = z.string().trim().toLowerCase().email().max(254);
const password = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(72, 'Password must be at most 72 characters') // bcrypt ignores bytes past 72
  .regex(/[a-z]/, 'Password needs a lowercase letter')
  .regex(/[A-Z]/, 'Password needs an uppercase letter')
  .regex(/[0-9]/, 'Password needs a number');

export const registerSchema = z.object({
  email,
  password,
  fullName: z.string().trim().min(2).max(100),
  phone: z.string().trim().min(7).max(20).optional(),
});
const loginSchema = z.object({ email, password: z.string().min(1).max(72) });

// ── routes ──
authRouter.post(
  '/register',
  authRateLimiter,
  validate(registerSchema),
  asyncHandler(async (req, res) => {
    sendSession(res, 201, await auth.register(req.body));
  }),
);

authRouter.post(
  '/login',
  authRateLimiter,
  validate(loginSchema),
  asyncHandler(async (req, res) => {
    sendSession(res, 200, await auth.login(req.body.email, req.body.password));
  }),
);

authRouter.post(
  '/refresh',
  authRateLimiter,
  asyncHandler(async (req, res) => {
    const token: string | undefined = req.cookies?.[REFRESH_COOKIE];
    if (!token) {
      res.status(401).json({
        error: { code: 'NO_REFRESH_TOKEN', message: 'No refresh token. Please log in.' },
      });
      return;
    }
    try {
      sendSession(res, 200, await auth.rotateSession(token));
    } catch (err) {
      clearRefreshCookie(res); // dead/stolen token → don't keep sending it
      throw err;
    }
  }),
);

authRouter.post(
  '/logout',
  asyncHandler(async (req, res) => {
    await auth.logout(req.cookies?.[REFRESH_COOKIE]);
    clearRefreshCookie(res);
    res.status(204).end();
  }),
);

authRouter.post(
  '/logout-all',
  authenticate,
  asyncHandler(async (req, res) => {
    await auth.revokeAllForUser(req.auth!.userId);
    clearRefreshCookie(res);
    res.status(204).end();
  }),
);

authRouter.get(
  '/me',
  authenticate,
  asyncHandler(async (req, res) => {
    res.json({ user: await auth.getUserById(req.auth!.userId) });
  }),
);
