import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { validate } from '../middleware/validate';
import { publicProductQuery, type PublicProductQuery } from '../schemas/catalog';
import * as products from '../services/product.service';

// Public: storefront catalog (ACTIVE products only, no cost price, no exact stock)
export const productsRouter = Router();

productsRouter.get(
  '/',
  validate(publicProductQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await products.listPublicProducts(req.query as unknown as PublicProductQuery));
  }),
);

productsRouter.get(
  '/:slug',
  asyncHandler(async (req, res) => {
    res.json({ product: await products.getPublicProduct(req.params.slug!) });
  }),
);
