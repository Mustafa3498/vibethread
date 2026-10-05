import { Role } from '@vibethread/database';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/async-handler';
import { Errors } from '../lib/errors';
import { authenticate, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import * as auth from '../services/auth.service';
import { registerSchema } from './auth';

export const adminRouter = Router();

// Everything below is ADMIN-only.
adminRouter.use(authenticate, requireRole(Role.ADMIN));

const createStaffSchema = registerSchema.extend({
  role: z.enum(['SHOPKEEPER', 'ADMIN']),
});

adminRouter.post(
  '/staff',
  validate(createStaffSchema),
  asyncHandler(async (req, res) => {
    res.status(201).json({ user: await auth.createStaff(req.body) });
  }),
);

const listSchema = z.object({
  role: z.nativeEnum(Role).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

adminRouter.get(
  '/users',
  validate(listSchema, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await auth.listUsers(req.query as unknown as z.infer<typeof listSchema>));
  }),
);

adminRouter.patch(
  '/users/:id/status',
  validate(z.object({ isActive: z.boolean() })),
  asyncHandler(async (req, res) => {
    if (req.params.id === req.auth!.userId) {
      throw Errors.badRequest('You cannot change your own status');
    }
    res.json({ user: await auth.setUserActive(req.params.id, req.body.isActive) });
  }),
);
