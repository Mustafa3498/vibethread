import { Role } from '@vibethread/database';
import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { authenticate, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import {
  idParam,
  staffOrdersQuery,
  staffStatusSchema,
  type StaffOrdersQuery,
  type StaffStatusInput,
} from '../schemas/shop';
import * as orders from '../services/order.service';

/** Fulfillment queue for SHOPKEEPER + ADMIN, mounted at /api/manage/orders. */
export const staffOrdersRouter = Router();
staffOrdersRouter.use(authenticate, requireRole(Role.SHOPKEEPER, Role.ADMIN));

staffOrdersRouter.get(
  '/',
  validate(staffOrdersQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await orders.listStaffOrders(req.query as unknown as StaffOrdersQuery));
  }),
);

staffOrdersRouter.get(
  '/:id',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ order: await orders.getStaffOrder(req.params.id!) });
  }),
);

/** PACKING -> READY_TO_SHIP -> SHIPPED (+ tracking/courier) -> DELIVERED; CANCELLED / RETURNED restock. */
staffOrdersRouter.patch(
  '/:id/status',
  validate(idParam, 'params'),
  validate(staffStatusSchema),
  asyncHandler(async (req, res) => {
    res.json({
      order: await orders.updateOrderStatus(req.params.id!, req.body as StaffStatusInput, req.auth!.userId),
    });
  }),
);
