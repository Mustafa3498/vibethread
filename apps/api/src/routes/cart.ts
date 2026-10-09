import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { addCartItemSchema, setCartItemSchema, variantParam } from '../schemas/shop';
import * as cart from '../services/cart.service';

/** The signed-in user's cart. Every change is also pushed over Socket.io (`cart:sync`). */
export const cartRouter = Router();
cartRouter.use(authenticate);

cartRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json({ cart: await cart.getCartPayload(req.auth!.userId) });
  }),
);

cartRouter.post(
  '/items',
  validate(addCartItemSchema),
  asyncHandler(async (req, res) => {
    const { variantId, quantity } = req.body as { variantId: string; quantity: number };
    res.status(201).json({ cart: await cart.addItem(req.auth!.userId, variantId, quantity) });
  }),
);

cartRouter.patch(
  '/items/:variantId',
  validate(variantParam, 'params'),
  validate(setCartItemSchema),
  asyncHandler(async (req, res) => {
    const { quantity } = req.body as { quantity: number };
    res.json({ cart: await cart.setQuantity(req.auth!.userId, req.params.variantId!, quantity) });
  }),
);

cartRouter.delete(
  '/items/:variantId',
  validate(variantParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ cart: await cart.removeItem(req.auth!.userId, req.params.variantId!) });
  }),
);

cartRouter.delete(
  '/',
  asyncHandler(async (req, res) => {
    res.json({ cart: await cart.clearCart(req.auth!.userId) });
  }),
);
