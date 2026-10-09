import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import {
  addressSchema,
  idParam,
  updateAddressSchema,
  type AddressInput,
  type UpdateAddressInput,
} from '../schemas/shop';
import * as addresses from '../services/address.service';

export const addressesRouter = Router();
addressesRouter.use(authenticate);

addressesRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json({ items: await addresses.listAddresses(req.auth!.userId) });
  }),
);

addressesRouter.post(
  '/',
  validate(addressSchema),
  asyncHandler(async (req, res) => {
    res.status(201).json({ address: await addresses.createAddress(req.auth!.userId, req.body as AddressInput) });
  }),
);

addressesRouter.patch(
  '/:id',
  validate(idParam, 'params'),
  validate(updateAddressSchema),
  asyncHandler(async (req, res) => {
    res.json({
      address: await addresses.updateAddress(req.auth!.userId, req.params.id!, req.body as UpdateAddressInput),
    });
  }),
);

addressesRouter.delete(
  '/:id',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    await addresses.deleteAddress(req.auth!.userId, req.params.id!);
    res.status(204).end();
  }),
);
