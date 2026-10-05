import { Role } from '@vibethread/database';
import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { authenticate, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import {
  addVariantsSchema,
  alertsQuery,
  createCategorySchema,
  createProductSchema,
  idParam,
  imageInput,
  imageOrderSchema,
  imageParams,
  inventoryListQuery,
  manageProductQuery,
  movementsQuery,
  stockAdjustSchema,
  updateCategorySchema,
  updateProductSchema,
  updateVariantSchema,
  variantIdParam,
  type InventoryListQuery,
  type ManageProductQuery,
} from '../schemas/catalog';
import * as categories from '../services/category.service';
import * as inventory from '../services/inventory.service';
import * as products from '../services/product.service';

/** Staff API: SHOPKEEPER + ADMIN. Hard delete and cost price are ADMIN-only. */
export const manageRouter = Router();
manageRouter.use(authenticate, requireRole(Role.SHOPKEEPER, Role.ADMIN));

const actor = (req: Express.Request) => ({ userId: req.auth!.userId, role: req.auth!.role });

// ───────────── categories ─────────────
manageRouter.post(
  '/categories',
  validate(createCategorySchema),
  asyncHandler(async (req, res) => {
    res.status(201).json({ category: await categories.createCategory(req.body) });
  }),
);
manageRouter.patch(
  '/categories/:id',
  validate(idParam, 'params'),
  validate(updateCategorySchema),
  asyncHandler(async (req, res) => {
    res.json({ category: await categories.updateCategory(req.params.id!, req.body) });
  }),
);
manageRouter.delete(
  '/categories/:id',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    await categories.deleteCategory(req.params.id!);
    res.status(204).end();
  }),
);

// ───────────── products ─────────────
manageRouter.get(
  '/products',
  validate(manageProductQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await products.listStaffProducts(req.query as unknown as ManageProductQuery, req.auth!.role));
  }),
);
manageRouter.get(
  '/products/:id',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.getStaffProduct(req.params.id!, req.auth!.role) });
  }),
);
manageRouter.post(
  '/products',
  validate(createProductSchema),
  asyncHandler(async (req, res) => {
    res.status(201).json({ product: await products.createProduct(req.body, actor(req)) });
  }),
);
manageRouter.patch(
  '/products/:id',
  validate(idParam, 'params'),
  validate(updateProductSchema),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.updateProduct(req.params.id!, req.body, actor(req)) });
  }),
);
manageRouter.post(
  '/products/:id/archive',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.archiveProduct(req.params.id!, actor(req)) });
  }),
);
manageRouter.post(
  '/products/:id/restore',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.restoreProduct(req.params.id!, actor(req)) });
  }),
);
manageRouter.delete(
  '/products/:id',
  requireRole(Role.ADMIN),
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    await products.deleteProduct(req.params.id!);
    res.status(204).end();
  }),
);

// ───────────── variants ─────────────
manageRouter.post(
  '/products/:id/variants',
  validate(idParam, 'params'),
  validate(addVariantsSchema),
  asyncHandler(async (req, res) => {
    res.status(201).json({ product: await products.addVariants(req.params.id!, req.body.variants, actor(req)) });
  }),
);
manageRouter.patch(
  '/variants/:variantId',
  validate(variantIdParam, 'params'),
  validate(updateVariantSchema),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.updateVariant(req.params.variantId!, req.body, actor(req)) });
  }),
);

// ───────────── images (URLs for now; direct upload to GCS comes later) ─────────────
manageRouter.post(
  '/products/:id/images',
  validate(idParam, 'params'),
  validate(imageInput),
  asyncHandler(async (req, res) => {
    res.status(201).json({ product: await products.addImage(req.params.id!, req.body, actor(req)) });
  }),
);
manageRouter.put(
  '/products/:id/images/order',
  validate(idParam, 'params'),
  validate(imageOrderSchema),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.reorderImages(req.params.id!, req.body.imageIds, actor(req)) });
  }),
);
manageRouter.delete(
  '/products/:id/images/:imageId',
  validate(imageParams, 'params'),
  asyncHandler(async (req, res) => {
    res.json({ product: await products.removeImage(req.params.id!, req.params.imageId!, actor(req)) });
  }),
);

// ───────────── inventory ─────────────
manageRouter.get(
  '/inventory',
  validate(inventoryListQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await inventory.listInventory(req.query as unknown as InventoryListQuery));
  }),
);
manageRouter.patch(
  '/inventory/:variantId',
  validate(variantIdParam, 'params'),
  validate(stockAdjustSchema),
  asyncHandler(async (req, res) => {
    res.json({ stock: await inventory.adjustStock(req.params.variantId!, req.body, req.auth!.userId) });
  }),
);
manageRouter.get(
  '/inventory-movements',
  validate(movementsQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await inventory.listMovements(req.query as never));
  }),
);

// ───────────── alerts ─────────────
manageRouter.get(
  '/alerts',
  validate(alertsQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await inventory.listAlerts(req.query as never));
  }),
);
manageRouter.post(
  '/alerts/read-all',
  asyncHandler(async (_req, res) => {
    res.json({ marked: await inventory.markAllAlertsRead() });
  }),
);
manageRouter.patch(
  '/alerts/:id/read',
  validate(idParam, 'params'),
  asyncHandler(async (req, res) => {
    await inventory.markAlertRead(req.params.id!);
    res.status(204).end();
  }),
);
