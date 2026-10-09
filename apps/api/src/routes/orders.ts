import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { idParam, myOrdersQuery, placeOrderSchema, type MyOrdersQuery, type PlaceOrderInput } from '../schemas/shop';
import * as orders from '../services/order.service';

/** POST /api/checkout: holds the cart's stock for 15 minutes and returns the priced cart. */
export const checkoutRouter = Router();
checkoutRouter.use(authenticate);

checkoutRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    res.json({ checkout: await orders.startCheckout(req.auth!.userId) });
  }),
);

/** The signed-in customer's own orders. */
export const ordersRouter = Router();
ordersRouter.use(authenticate);

ordersRouter.post(
  '/',
  validate(placeOrderSchema),
  asyncHandler(async (req, res) => {
    res.status(201).json({ order: await orders.placeOrder(req.auth!.userId, req.body as PlaceOrderInput) });
  }),
);

ordersRouter.get(
  '/',
  validate(myOrdersQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await orders.listMyOrders(req.auth!.userId, req.query as unknown as MyOrdersQuery));
  }),
);

ordersRouter.get(
  '/:id',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ order: await orders.getMyOrder(req.auth!.userId, req.params.id!) });
  }),
);

ordersRouter.post(
  '/:id/cancel',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ order: await orders.cancelMyOrder(req.auth!.userId, req.params.id!) });
  }),
);
