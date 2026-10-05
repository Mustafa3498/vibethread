import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import * as categories from '../services/category.service';

// Public: storefront navigation
export const categoriesRouter = Router();

categoriesRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    res.json({ items: await categories.getCategoryTree() });
  }),
);

categoriesRouter.get(
  '/:slug',
  asyncHandler(async (req, res) => {
    res.json({ category: await categories.getCategoryBySlug(req.params.slug!) });
  }),
);
